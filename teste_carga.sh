#!/bin/bash
# Script de Teste de Carga - Pool de Conexões
# Salve como: test-load.sh
# Dar permissão: chmod +x test-load.sh

REQUESTS=${1:-100}
CONCURRENT=${2:-20}
URL=${3:-"http://localhost:80/users"}

echo "========================================"
echo "Teste de Carga - Pool de Conexões"
echo "========================================"
echo "URL: $URL"
echo "Requisições: $REQUESTS"
echo "Concorrentes: $CONCURRENT"
echo ""

# Resetar estatísticas
echo "Resetando estatísticas..."
curl -s -X POST http://localhost:9000/metrics/reset > /dev/null
echo ""

# Usando Apache Bench (ab)
if command -v ab &> /dev/null; then
    echo "Usando Apache Bench (ab)..."
    echo ""
    ab -n $REQUESTS -c $CONCURRENT $URL
    echo ""
    
# Usando wrk (mais moderno)
elif command -v wrk &> /dev/null; then
    echo "Usando wrk..."
    echo ""
    DURATION=$((REQUESTS / CONCURRENT))
    if [ $DURATION -lt 10 ]; then
        DURATION=10
    fi
    wrk -t$CONCURRENT -c$CONCURRENT -d${DURATION}s $URL
    echo ""
    
# Fallback para curl
else
    echo "Usando curl (instale 'ab' ou 'wrk' para testes melhores)..."
    echo ""
    
    SUCCESS=0
    FAILED=0
    
    for ((i=1; i<=$REQUESTS; i++)); do
        if curl -s -o /dev/null -w "%{http_code}" $URL | grep -q "200"; then
            ((SUCCESS++))
        else
            ((FAILED++))
        fi
        
        if [ $((i % 10)) -eq 0 ]; then
            echo -n "."
        fi
    done
    
    echo ""
    echo ""
    echo "Sucesso: $SUCCESS"
    echo "Falhas: $FAILED"
    echo ""
fi

# Obter métricas do servidor
echo "========================================"
echo "Métricas do Servidor"
echo "========================================"
curl -s http://localhost:9000/metrics | python3 -m json.tool 2>/dev/null || curl -s http://localhost:9000/metrics

echo ""
echo ""
echo "Teste concluído!"