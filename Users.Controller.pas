unit Users.Controller;

interface

uses
  Horse, System.JSON, FireDAC.Comp.Client, System.DateUtils, System.SysUtils,
  FireDAC.Stan.Def, FireDAC.Phys.SQLite, FireDAC.DApt, FireDAC.Stan.Async, ConnectionPool;

procedure RegisterRoutes;

implementation

procedure GetPoolMetrics(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Metrics: TJSONObject;
begin
  Metrics := TJSONObject.Create;
  try
    Metrics.AddPair('pool', TConnectionPool.Instance.GetMetrics);
    Metrics.AddPair('requests', RequestStats.GetStats);
    Res.Send<TJSONObject>(Metrics);
  except
    Metrics.Free;
    raise;
  end;
end;

procedure ResetStats(Req: THorseRequest; Res: THorseResponse; Next: TProc);
begin
  RequestStats.Reset;
  TConnectionPool.Instance.Reset;
  Res.Send(TJSONObject.Create.AddPair('message', 'Estat�sticas resetadas'));
end;


procedure GetUsers(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Connection: TFDConnection;
  Query: TFDQuery;
  Users: TJSONArray;
  User: TJSONObject;
  StartTime: TDateTime;
  ElapsedTime: Int64;
  Retries: Integer;
begin
  StartTime := Now;
  Connection := nil;
  Query := nil;
  Retries := 0;

  while Retries < 3 do
  try
    Connection := TConnectionPool.Instance.GetConnection;
    Query := TFDQuery.Create(nil);
    Query.Connection := Connection;
    
    Query.SQL.Text := 'SELECT * FROM users';
    Query.Open;

    // Simular processamento (remover em produção)
//    Sleep(Random(100) + 50); // 50-150ms

    Users := TJSONArray.Create;
    try
      while not Query.Eof do
      begin
        User := TJSONObject.Create;
        User.AddPair('id', Query.FieldByName('id').AsString);
        User.AddPair('name', Query.FieldByName('name').AsString);
        User.AddPair('email', Query.FieldByName('email').AsString);
        Users.AddElement(User);
        Query.Next;
      end;

      ElapsedTime := MilliSecondsBetween(Now, StartTime);
      RequestStats.RecordRequest(ElapsedTime, True);

      Res.Send<TJSONArray>(Users);
      Break;
    except
      Users.Free;
      raise;
    end;
  except
    on E: Exception do
    begin
      Inc(Retries);
      if Retries >= 3 then
      begin
        ElapsedTime := MilliSecondsBetween(Now, StartTime);
        RequestStats.RecordRequest(ElapsedTime, False);
        Res.Status(500).Send(TJSONObject.Create.AddPair('error', E.Message));
      end
      else
        Sleep(100); // Wait before retry
    end;
  end;

  if Assigned(Query) then
    Query.Free;
  if Assigned(Connection) then
    TConnectionPool.Instance.ReleaseConnection(Connection);
end;

procedure CreateUser(Req: THorseRequest; Res: THorseResponse; Next: TProc);
var
  Connection: TFDConnection;
  Query: TFDQuery;
  Body: TJSONObject;
  Name, Email: string;
begin
  Connection := TConnectionPool.Instance.GetConnection;
  Query := TFDQuery.Create(nil);
  try
    Body := Req.Body<TJSONObject>;
    Name := Body.GetValue<string>('name');
    Email := Body.GetValue<string>('email');

    Query.Connection := Connection;
    Query.SQL.Text := 'INSERT INTO users (name, email) VALUES (:name, :email)';
    Query.ParamByName('name').AsString := Name;
    Query.ParamByName('email').AsString := Email;
    Query.ExecSQL;

    Res.Status(201).Send('Usu�rio criado com sucesso');
  finally
    Query.Free;
    TConnectionPool.Instance.ReleaseConnection(Connection);
  end;
end;

procedure RegisterRoutes;
begin
  THorse.Get('/users', GetUsers);
  THorse.Post('/users', CreateUser);
  THorse.Get('/metrics', GetPoolMetrics);
  THorse.Post('/metrics/reset', ResetStats);
end;

end.
