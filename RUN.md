# HIVE — Como executar (PCS 5703, MAPC 2022)

Time multi-agente **HIVE** (JaCaMo: Jason + CArtAgO + MOISE+) para o cenário
*Agents Assemble* do MAPC 2022.

## Pré-requisitos
- **Java 21** (JDK)
- **Gradle** (ou use um gradle instalado no sistema)
- **Servidor MASSim 2022-1.1** (plataforma oficial da competição). Não está
  incluído neste pacote por ser a plataforma padrão; baixe o release em
  <https://github.com/agentcontest/massim_2022/releases> (arquivo
  `server-2022-*-jar-with-dependencies.jar`).

## Passos

### 1) Iniciar o servidor MASSim (Terminal 1)
A partir da pasta do servidor MASSim, aponte para uma das configurações em `conf/`:

```bash
java -jar server-2022-1.1-jar-with-dependencies.jar \
     -conf <caminho>/conf/OfficialTwoTeamsConfig.json --monitor
```

Configurações incluídas em `conf/`:
- `OfficialTwoTeamsConfig.json` — cenário oficial (2 times, grid 70×70, 20 agentes, posição relativa);
- `OfficialTestConfig.json` — cenário oficial com 1 time (treino);
- `TestConfig.json` — cenário de desenvolvimento (grid 40×40, posição absoluta).

Aguarde o servidor subir (porta 12300). O monitor fica em <http://localhost:8000/>.

### 2) Iniciar os agentes HIVE (Terminal 2)
Na raiz deste pacote:

```bash
gradle run
```

Para o grid oficial 70×70, passe as dimensões:

```bash
gradle run -PgridW=70 -PgridH=70
```

Os 20 agentes conectam automaticamente via EIS (config em `eismassimconfig.json`)
e a simulação inicia após a janela de conexão do servidor.

## Estrutura do código-fonte

| Caminho | Descrição |
|---|---|
| `hive.jcm` | Configuração JaCaMo: instancia os 20 agentes e a organização MOISE+ |
| `eismassimconfig.json` | Conexão EIS → MASSim (20 entidades `connectionA1..20`) |
| `build.gradle`, `settings.gradle` | Build Gradle (Java 21) |
| `logging.properties` | Configuração de logging |
| `lib/eismassim-4.5-...jar` | Ponte EIS (dependência local necessária) |
| `src/agt/*.asl` | Agentes por papel: `squad_leader`, `collector`, `assembler`, `sentinel` |
| `src/agt/common/*.asl` | Módulos comuns (percepção, navegação, coleta, connect, adoção de papel, etc.) |
| `src/env/env/*.java` | Artefatos CArtAgO (SharedMap, TaskBoard, SquadCoordinator, HiveDashboard) |
| `src/env/connection/*.java` | Ponte EIS e tradução EIS↔Jason |
| `src/java/hive/*.java` | Utilitários (config de grid, frame relativo, direção adjacente) |
| `src/org/hive_org.xml` | Especificação organizacional MOISE+ |

Todos os arquivos-fonte estão comentados explicando a lógica do programa.
