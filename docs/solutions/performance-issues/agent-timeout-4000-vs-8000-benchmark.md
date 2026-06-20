# Benchmark: agentTimeout 4000ms vs 8000ms (cenário oficial vs HIVE)

## Contexto

O MAPC 2022 usa `agentTimeout: 4000ms` (config oficial `sim1.json`). O HIVE
roda com `8000ms` (margem deliberada para o overhead JaCaMo/EIS/CArtAgO). O P3
do plano "Cenário Oficial" pediu para medir se 4000ms é viável.

## Método

`FastTestConfig` (100 steps, 40x40, cave 0.45, **20 agentes**, seed 17,
absolutePosition=true), com o fix `awaitTime=500` (EISAccess) já aplicado.
Contagem de "No valid action available in time for agent" no log do servidor.

## Resultado

| Config | Timeouts (100 steps, 20 agentes) | Por step | % das ações de agente |
|--------|----------------------------------|----------|------------------------|
| 8000ms (baseline) | 40 | 0,40 | 2,0% |
| 4000ms | 95 | 0,95 | 4,75% |

Reduzir para 4000ms **mais que dobra** os timeouts (40 -> 95). A 4,75% já fica no
limite do critério de aceitação (<5%), e o cenário oficial é mais pesado (70x70,
cave 0.6, caminhos A* mais longos por step), o que empurraria a taxa acima de 5%.

## Decisão

Manter **8000ms** no `OfficialTestConfig.json`. É uma divergência consciente da
config oficial, justificada pelo overhead do stack JaCaMo (cada operação CArtAgO
é serializada; 20 agentes Jason competem pela thread do artefato). Documentar a
diferença no relatório como limitação conhecida do middleware, não da estratégia.

Caminhos para fechar a folga no futuro (gated por medição):
- Reduzir contenção CArtAgO (ingestão em lote por step — tentada e revertida como
  neutra na investigação do EIS; revisitar com profiling correto).
- Paralelizar a percepção/decisão fora do artefato compartilhado.
