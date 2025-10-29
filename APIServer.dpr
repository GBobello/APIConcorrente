program APIServer;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  System.JSON,
  Horse,
  Horse.Jhonson,
  Horse.CORS,
  ConnectionPool in 'ConnectionPool.pas',
  Users.Controller in 'Users.Controller.pas';

// *** INÍCIO DA MODIFICAÇÃO ***
const
  // Cole o caminho que você encontrou no passo 1
  LINUX_SQLITE_LIB = '/lib/x86_64-linux-gnu/libsqlite3.so';

  // Defina o caminho onde seu banco estará no servidor
  LINUX_DB_PATH = '/var/www/apiserver/db/database';

  // String de conexão para Windows (para depuração local)
  WIN_CONNECTION_STRING = 'DriverID=SQLite;Database=D:\projects\Concorrente_Delphi\db\database';

  // String de conexão para Linux (com os caminhos corretos)
  LINUX_CONNECTION_STRING = 'DriverID=SQLite;Database=%s;VendorLib=%s';
// *** FIM DA MODIFICAÇÃO ***

procedure ConfigureRoutes;
begin
  // Rota de teste simples
  THorse.Get('/ping',
    procedure(Req: THorseRequest; Res: THorseResponse; Next: TProc)
    begin
      Res.Send('pong');
    end);

  Users.Controller.RegisterRoutes;
end;


begin
  try
    // Configurar middlewares
    THorse
      .Use(Jhonson)
      .Use(CORS);

    var ConnString: string;
    {$IFDEF MSWINDOWS}
      ConnString := WIN_CONNECTION_STRING;
    {$ENDIF}

    {$IFDEF LINUX}
      // Formata a string de conexão com os caminhos corretos
      ConnString := Format(LINUX_CONNECTION_STRING, [LINUX_DB_PATH, LINUX_SQLITE_LIB]);
    {$ENDIF}

    // Increase pool size and max connections
    TConnectionPool.Initialize(50, ConnString);

    RequestStats := TRequestStats.Create;

    // Configurar concorr�ncia
    THorse.MaxConnections := 50;

    // Registrar rotas
    ConfigureRoutes;

    // Iniciar servidor
    Writeln('==================================================');
    Writeln('Servidor de Teste - Pool de Conex�es');
    Writeln('==================================================');
    Writeln('Porta: 9000');
    Writeln('Pool: 5 conex�es (PEQUENO para teste de carga)');
    Writeln('Max Threads: 50');
    Writeln('');
    Writeln('Endpoints:');
    Writeln('  GET  http://localhost:9000/ping');
    Writeln('  GET  http://localhost:9000/users');
    Writeln('  POST http://localhost:9000/users');
    Writeln('  GET  http://localhost:9000/metrics');
    Writeln('  POST http://localhost:9000/metrics/reset');
    Writeln('');
    Writeln('Pressione ENTER para parar...');
    Writeln('==================================================');

    THorse.Listen(9000);

    Readln;

    Writeln('Servidor encerrado.');
    RequestStats.Free;
    TConnectionPool.Finalize;
  except
    on E: Exception do
    begin
      Writeln('ERRO: ' + E.Message);
      Readln;
    end;
  end;
end.
