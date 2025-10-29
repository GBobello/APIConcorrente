unit ConnectionPool;

interface

uses
  System.SyncObjs, System.Generics.Collections, System.SysUtils, FireDAC.Comp.Client,
  FireDAC.Stan.Def, FireDAC.Phys.SQLite, System.JSON, System.DateUtils;

type
  // Pool de Conexões com Métricas
  TConnectionPool = class
  private
    FConnections: TThreadList<TFDConnection>;
    FMaxConnections: Integer;
    FConnectionString: string;
    FTotalRequests: Integer;
    FActiveConnections: Integer;
    FWaitingRequests: Integer;
    FLock: TCriticalSection;
    FConnectionAvailable: TEvent;
    class var FInstance: TConnectionPool;

    procedure IncActiveConnections;
    procedure DecActiveConnections;
    procedure DecWaitingRequests;
  public
    constructor Create(AMaxConnections: Integer; const AConnectionString: string);
    destructor Destroy; override;

    function GetConnection: TFDConnection;
    procedure ReleaseConnection(AConnection: TFDConnection);

    // Métricas
    function GetMetrics: TJSONObject;
    function GetAvailableConnections: Integer;
    procedure Reset;

    class function Instance: TConnectionPool;
    class procedure Initialize(AMaxConnections: Integer; const AConnectionString: string);
    class procedure Finalize;
  end;

  // Estatísticas de Requisições
  TRequestStats = class
  private
    FTotalRequests: Integer;
    FSuccessRequests: Integer;
    FErrorRequests: Integer;
    FTotalTime: Int64;
    FMinTime: Int64;
    FMaxTime: Int64;
    FLock: TCriticalSection;
  public
    constructor Create;
    destructor Destroy; override;

    procedure RecordRequest(ATime: Int64; ASuccess: Boolean);
    function GetStats: TJSONObject;
    procedure Reset;
  end;

var
  RequestStats: TRequestStats;

implementation

{ TConnectionPool }

constructor TConnectionPool.Create(AMaxConnections: Integer; const AConnectionString: string);
var
  I: Integer;
  Conn: TFDConnection;
begin
  FMaxConnections := AMaxConnections;
  FConnectionString := AConnectionString;
  FConnections := TThreadList<TFDConnection>.Create;
  FLock := TCriticalSection.Create;
  FConnectionAvailable := TEvent.Create(nil, True, False, '');
  FTotalRequests := 0;
  FActiveConnections := 0;
  FWaitingRequests := 0;

  Writeln(Format('Criando pool com %d conexões...', [AMaxConnections]));

  for I := 0 to FMaxConnections - 1 do
  begin
    Conn := TFDConnection.Create(nil);
    Conn.ConnectionString := FConnectionString;
    try
      Conn.Connected := True;
      FConnections.Add(Conn);
      Write('.');
    except
      on E: Exception do
      begin
        Writeln;
        Writeln(Format('Erro ao criar conexão %d: %s', [I, E.Message]));
        Conn.Free;
      end;
    end;
  end;
  Writeln;
  Writeln(Format('Pool criado com sucesso! (%d conexões ativas)',
    [FConnections.LockList.Count]));
  FConnections.UnlockList;
end;

destructor TConnectionPool.Destroy;
var
  List: TList<TFDConnection>;
  Conn: TFDConnection;
begin
  List := FConnections.LockList;
  try
    for Conn in List do
      Conn.Free;
    List.Clear;
  finally
    FConnections.UnlockList;
  end;
  FConnections.Free;
  FLock.Free;
  FConnectionAvailable.Free;
  inherited;
end;

procedure TConnectionPool.IncActiveConnections;
begin
  FLock.Enter;
  try
    Inc(FActiveConnections);
  finally
    FLock.Leave;
  end;
end;

procedure TConnectionPool.DecActiveConnections;
begin
  FLock.Enter;
  try
    Dec(FActiveConnections);
  finally
    FLock.Leave;
  end;
end;

procedure TConnectionPool.DecWaitingRequests;
begin
  FLock.Enter;
  try
    Dec(FWaitingRequests);
  finally
    FLock.Leave;
  end;
end;

function TConnectionPool.GetConnection: TFDConnection;
var
  List: TList<TFDConnection>;
  StartTime: TDateTime;
begin
  Result := nil;
  StartTime := Now;

  FLock.Enter;
  try
    Inc(FTotalRequests);
    Inc(FWaitingRequests);
  finally
    FLock.Leave;
  end;

  // Tentar obter conexão
  while Result = nil do
  begin
    List := FConnections.LockList;
    try
      if List.Count > 0 then
      begin
        Result := List.First;
        List.Delete(0);
      end;
    finally
      FConnections.UnlockList;
    end;

    if Result = nil then
    begin
      if FConnectionAvailable.WaitFor(5000) = wrTimeout then
      begin
        DecWaitingRequests;
        raise Exception.Create('Pool de conexões esgotado - timeout');
      end;
    end;
  end;

  DecWaitingRequests;

  if not Result.Connected then
    Result.Connected := True;

  IncActiveConnections;

  // Log se esperou muito
  if MilliSecondsBetween(Now, StartTime) > 500 then
    Writeln(Format('AVISO: Requisição esperou %dms por conexão',
      [MilliSecondsBetween(Now, StartTime)]));
end;

procedure TConnectionPool.ReleaseConnection(AConnection: TFDConnection);
begin
  if Assigned(AConnection) then
  begin
    DecActiveConnections;
    FConnections.Add(AConnection);
    FConnectionAvailable.SetEvent;
  end;
end;

procedure TConnectionPool.Reset;
begin
  FLock.Enter;
  try
    FTotalRequests := 0;
    FActiveConnections := 0;
    FWaitingRequests := 0;
  finally
    FLock.Leave;
  end;
end;

function TConnectionPool.GetAvailableConnections: Integer;
var
  List: TList<TFDConnection>;
begin
  List := FConnections.LockList;
  try
    Result := List.Count;
  finally
    FConnections.UnlockList;
  end;
end;

function TConnectionPool.GetMetrics: TJSONObject;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('max_connections', TJSONNumber.Create(FMaxConnections));
    Result.AddPair('available_connections', TJSONNumber.Create(GetAvailableConnections));
    Result.AddPair('active_connections', TJSONNumber.Create(FActiveConnections));
    Result.AddPair('waiting_requests', TJSONNumber.Create(FWaitingRequests));
    Result.AddPair('total_requests', TJSONNumber.Create(FTotalRequests));
    Result.AddPair('utilization_percent',
      TJSONNumber.Create(Round((FActiveConnections / FMaxConnections) * 100)));
  finally
    FLock.Leave;
  end;
end;

class function TConnectionPool.Instance: TConnectionPool;
begin
  Result := FInstance;
end;

class procedure TConnectionPool.Initialize(AMaxConnections: Integer; const AConnectionString: string);
begin
  if not Assigned(FInstance) then
    FInstance := TConnectionPool.Create(AMaxConnections, AConnectionString);
end;

class procedure TConnectionPool.Finalize;
begin
  if Assigned(FInstance) then
    FreeAndNil(FInstance);
end;

{ TRequestStats }

constructor TRequestStats.Create;
begin
  FLock := TCriticalSection.Create;
  FMinTime := MaxInt;
  FMaxTime := 0;
end;

destructor TRequestStats.Destroy;
begin
  FLock.Free;
  inherited;
end;

procedure TRequestStats.RecordRequest(ATime: Int64; ASuccess: Boolean);
begin
  FLock.Enter;
  try
    Inc(FTotalRequests);
    if ASuccess then
      Inc(FSuccessRequests)
    else
      Inc(FErrorRequests);

    Inc(FTotalTime, ATime);

    if ATime < FMinTime then
      FMinTime := ATime;
    if ATime > FMaxTime then
      FMaxTime := ATime;
  finally
    FLock.Leave;
  end;
end;

function TRequestStats.GetStats: TJSONObject;
var
  AvgTime: Int64;
begin
  FLock.Enter;
  try
    Result := TJSONObject.Create;
    Result.AddPair('total_requests', TJSONNumber.Create(FTotalRequests));
    Result.AddPair('success_requests', TJSONNumber.Create(FSuccessRequests));
    Result.AddPair('error_requests', TJSONNumber.Create(FErrorRequests));

    if FTotalRequests > 0 then
      AvgTime := FTotalTime div FTotalRequests
    else
      AvgTime := 0;

    Result.AddPair('avg_time_ms', TJSONNumber.Create(AvgTime));
    Result.AddPair('min_time_ms', TJSONNumber.Create(FMinTime));
    Result.AddPair('max_time_ms', TJSONNumber.Create(FMaxTime));
  finally
    FLock.Leave;
  end;
end;

procedure TRequestStats.Reset;
begin
  FLock.Enter;
  try
    FTotalRequests := 0;
    FSuccessRequests := 0;
    FErrorRequests := 0;
    FTotalTime := 0;
    FMinTime := MaxInt;
    FMaxTime := 0;
  finally
    FLock.Leave;
  end;
end;
end.
