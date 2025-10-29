# Script de Teste de Carga - Pool de Conexões
# Salve como: test-load.ps1

param(
    [int]$Requests = 100,
    [int]$Concurrent = 20,
    [string]$Url = "http://localhost:9000/users"
)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Teste de Carga - Pool de Conexões" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "URL: $Url"
Write-Host "Requisições: $Requests"
Write-Host "Concorrentes: $Concurrent"
Write-Host ""

# Resetar estatísticas antes do teste
try {
    Invoke-RestMethod -Uri "http://localhost:9000/metrics/reset" -Method POST | Out-Null
    Write-Host "Estatísticas resetadas" -ForegroundColor Green
} catch {
    Write-Host "Aviso: Não foi possível resetar estatísticas" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Iniciando teste..." -ForegroundColor Yellow
$startTime = Get-Date

# Array para armazenar os jobs
$jobs = @()

# Criar requisições concorrentes
for ($i = 1; $i -le $Requests; $i++) {
    $jobs += Start-Job -ScriptBlock {
        param($url)
        $start = Get-Date
        $maxRetries = 3
        $retryCount = 0
        
        while ($retryCount -lt $maxRetries) {
            try {
                $response = Invoke-RestMethod -Uri $url -TimeoutSec 30
                $elapsed = ((Get-Date) - $start).TotalMilliseconds
                return @{
                    Success = $true
                    Time = $elapsed
                    StatusCode = 200
                    Retries = $retryCount
                }
            } catch {
                $retryCount++
                if ($retryCount -ge $maxRetries) {
                    $elapsed = ((Get-Date) - $start).TotalMilliseconds
                    return @{
                        Success = $false
                        Time = $elapsed
                        Error = $_.Exception.Message
                        Retries = $retryCount
                    }
                }
                Start-Sleep -Milliseconds 100
            }
        }
    } -ArgumentList $Url
    
    # Controlar concorrência
    if (($jobs | Where-Object { $_.State -eq 'Running' }).Count -ge $Concurrent) {
        $jobs | Where-Object { $_.State -eq 'Running' } | Wait-Job -Any | Out-Null
    }
    
    # Mostrar progresso
    if ($i % 10 -eq 0) {
        Write-Host "." -NoNewline
    }
}

Write-Host ""
Write-Host "Aguardando conclusão de todas as requisições..." -ForegroundColor Yellow

# Aguardar todos os jobs
$jobs | Wait-Job | Out-Null

$endTime = Get-Date
$totalTime = ($endTime - $startTime).TotalSeconds

# Coletar resultados
$results = $jobs | Receive-Job
$jobs | Remove-Job

# Calcular estatísticas
$successful = ($results | Where-Object { $_.Success }).Count
$failed = ($results | Where-Object { -not $_.Success }).Count
$times = ($results | Where-Object { $_.Success }).Time

if ($times.Count -gt 0) {
    $avgTime = ($times | Measure-Object -Average).Average
    $minTime = ($times | Measure-Object -Minimum).Minimum
    $maxTime = ($times | Measure-Object -Maximum).Maximum
} else {
    $avgTime = 0
    $minTime = 0
    $maxTime = 0
}

# Exibir resultados
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Resultados do Teste" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tempo total: $([math]::Round($totalTime, 2))s"
Write-Host "Requisições/segundo: $([math]::Round($Requests / $totalTime, 2))"
Write-Host ""
Write-Host "Sucesso: $successful" -ForegroundColor Green
Write-Host "Falhas: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "Tempo médio: $([math]::Round($avgTime, 2))ms"
Write-Host "Tempo mínimo: $([math]::Round($minTime, 2))ms"
Write-Host "Tempo máximo: $([math]::Round($maxTime, 2))ms"

# Obter métricas do servidor
Write-Host ""
Write-Host "Obtendo métricas do servidor..." -ForegroundColor Yellow

try {
    $metrics = Invoke-RestMethod -Uri "http://localhost:9000/metrics"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Métricas do Pool de Conexões" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Conexões máximas: $($metrics.pool.max_connections)"
    Write-Host "Conexões disponíveis: $($metrics.pool.available_connections)"
    Write-Host "Conexões ativas: $($metrics.pool.active_connections)"
    Write-Host "Utilização: $($metrics.pool.utilization_percent)%"
    Write-Host "Total de requisições: $($metrics.pool.total_requests)"
    
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Estatísticas de Requisições (Servidor)" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total: $($metrics.requests.total_requests)"
    Write-Host "Sucesso: $($metrics.requests.success_requests)" -ForegroundColor Green
    Write-Host "Erros: $($metrics.requests.error_requests)" -ForegroundColor $(if ($metrics.requests.error_requests -gt 0) { "Red" } else { "Green" })
    Write-Host "Tempo médio: $($metrics.requests.avg_time_ms)ms"
    Write-Host "Tempo mínimo: $($metrics.requests.min_time_ms)ms"
    Write-Host "Tempo máximo: $($metrics.requests.max_time_ms)ms"
    
} catch {
    Write-Host "Erro ao obter métricas: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "Teste concluído!" -ForegroundColor Green
Read-Host -Prompt "Pressione ENTER para sair"