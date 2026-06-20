# ─────────────────────────────────────────────────────────────
#  HIVE MAS — Makefile
#  Comandos para rodar servidor, agentes, testes e dashboard
# ─────────────────────────────────────────────────────────────

MASSIM_JAR  := massim_2022/server/target/server-2022-1.1-jar-with-dependencies.jar
MONITOR_PORT := 8000

# Configurações disponíveis (override: make server CONFIG=conf/FastTestConfig.json)
CONFIG       ?= conf/TestConfig.json
GRID_W       ?= 40
GRID_H       ?= 40

# ─────────────────  Targets principais  ─────────────────────

.PHONY: help all server agents test fast official dashboard dashboard-install clean stop status

help: ## Mostra esta ajuda
	@echo ""
	@echo "  HIVE MAS — Comandos disponíveis"
	@echo "  ════════════════════════════════════════════════════════"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  ── Fluxo típico ──"
	@echo "  Terminal 1:  make server"
	@echo "  Terminal 2:  make agents        (espere o servidor mostrar 'Starting tournament')"
	@echo "  Terminal 3:  make dashboard     (opcional, abre http://localhost:5173)"
	@echo ""
	@echo "  ── Variáveis ──"
	@echo "  CONFIG=conf/TestConfig.json     Arquivo de config do servidor (default)"
	@echo "  GRID_W=40  GRID_H=40           Dimensões do grid dos agentes"
	@echo ""

# ─────────────────  Simulação  ──────────────────────────────

server: ## Inicia o servidor MASSim (monitor em http://localhost:8000)
	@echo "╔══════════════════════════════════════════════╗"
	@echo "║  MASSim Server — $(CONFIG)"
	@echo "║  Monitor: http://localhost:$(MONITOR_PORT)"
	@echo "╚══════════════════════════════════════════════╝"
	cd massim_2022 && java -jar ../$(MASSIM_JAR) -conf ../$(CONFIG) --monitor

agents: ## Inicia os 15 agentes HIVE (JaCaMo)
	@echo "╔══════════════════════════════════════════════╗"
	@echo "║  HIVE Agents — Grid $(GRID_W)x$(GRID_H)"
	@echo "║  Mind Inspector: http://localhost:3272"
	@echo "╚══════════════════════════════════════════════╝"
	gradle run -PgridW=$(GRID_W) -PgridH=$(GRID_H)

# ─── Atalhos por cenário ────────────────────────────────────

fast: ## Roda cenário rápido (100 steps, 40x40, absolutePosition=true)
	$(MAKE) server CONFIG=conf/FastTestConfig.json

dev: ## Roda cenário dev completo (800 steps, 40x40, absolutePosition=true)
	$(MAKE) server CONFIG=conf/TestConfig.json

official: ## Roda servidor cenário oficial MAPC (750 steps, 70x70, 20 agentes, absolutePosition=false)
	$(MAKE) server CONFIG=conf/OfficialTestConfig.json

official-2teams: ## Roda servidor oficial com 2 times (HIVE vs dummy)
	$(MAKE) server CONFIG=conf/OfficialTwoTeamsConfig.json

agents-official: ## Inicia agentes HIVE (time A) para cenário oficial (grid 70x70)
	$(MAKE) agents GRID_W=70 GRID_H=70

DUMMY_JAR := massim_2022/javaagents/target/javaagents-2022-1.1-jar-with-dependencies.jar

opponent: ## Inicia o time B dummy (massim BasicAgents) — usar com official-2teams
	@echo "╔══════════════════════════════════════════════╗"
	@echo "║  Time B (dummy BasicAgents) — 20 agentes"
	@echo "╚══════════════════════════════════════════════╝"
	java -jar $(DUMMY_JAR) conf/teamB

# ─────────────────  Testes  ─────────────────────────────────

test: ## Roda todos os testes JUnit
	@echo "══ Rodando testes JUnit ══"
	gradle test

build: ## Compila o projeto (sem rodar)
	gradle classes

# ─────────────────  Dashboard  ──────────────────────────────

dashboard-install: ## Instala dependências do dashboard
	cd dashboard && npm install

dashboard: ## Inicia o dashboard (http://localhost:5173)
	@echo "╔══════════════════════════════════════════════╗"
	@echo "║  HIVE Command Center"
	@echo "║  http://localhost:5173"
	@echo "╚══════════════════════════════════════════════╝"
	cd dashboard && npm run dev

# ─────────────────  Utilitários  ────────────────────────────

status: ## Mostra processos do HIVE rodando
	@echo "══ Processos HIVE ══"
	@ps aux | grep -E 'massim|JaCaMo|gradle.*run|vite' | grep -v grep || echo "  Nenhum processo encontrado."

stop: ## Para todos os processos (servidor + agentes + dashboard)
	@echo "Parando processos..."
	@-pkill -f 'server-2022.*jar' 2>/dev/null && echo "  ✓ Servidor MASSim parado" || echo "  - Servidor não estava rodando"
	@-pkill -f 'JaCaMoLauncher' 2>/dev/null && echo "  ✓ Agentes JaCaMo parados" || echo "  - Agentes não estavam rodando"
	@-pkill -f 'gradle.*run' 2>/dev/null && echo "  ✓ Gradle parado" || echo "  - Gradle não estava rodando"
	@-pkill -f 'vite.*dashboard' 2>/dev/null && echo "  ✓ Dashboard parado" || echo "  - Dashboard não estava rodando"
	@echo "Pronto."

clean: ## Limpa artefatos de build
	gradle clean
	rm -rf massim_2022/results/* massim_2022/logs/* massim_2022/replays/*
	@echo "✓ Build e resultados limpos."

results: ## Mostra scores dos resultados salvos
	@echo "══ Resultados ══"
	@find massim_2022/results -name '*.json' -exec echo -n "  " \; -exec basename {} \; -exec cat {} \; -exec echo "" \; 2>/dev/null || echo "  Nenhum resultado encontrado."

submodule: ## Inicializa o submódulo massim_2022
	git submodule update --init --recursive

# ─────────────────  Receita completa  ───────────────────────

all: submodule test ## Setup completo: submódulo + testes
	@echo ""
	@echo "✓ Tudo pronto! Use 'make help' para ver os comandos."
