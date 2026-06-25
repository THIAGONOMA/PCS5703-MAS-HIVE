package env;

// ============================================================
// SquadCoordinator.java — Artefato CArtAgO de coordenação de squads
// ------------------------------------------------------------
// Onde o conceito de "esquadrão" do HIVE é realizado em tempo de
// execução (o MOISE+ usa estrutura achatada). Mantém:
//   - a composição dos 4 squads e o papel de cada agente;
//   - o "pool universal de soloists" (soloistBusy): quem está livre
//     pode pegar qualquer tarefa, independentemente do papel;
//   - meeting points, prontidão (signal_ready/all_ready) e atribuição
//     de blocos para a coordenação multi-bloco (connect);
//   - a seleção do soloist livre mais próximo de um dispenser
//     (find_free_soloist), usando distância toroidal.
// Estado em ConcurrentHashMap pois é acessado por vários agentes.
// ============================================================

import cartago.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class SquadCoordinator extends Artifact {

    ConcurrentHashMap<String, String> agentSquad;          // agente -> id do squad
    ConcurrentHashMap<String, List<String>> squadMembers;  // squad  -> membros
    ConcurrentHashMap<String, String> squadRole;           // agente -> papel (leader/collector/...)
    private ConcurrentHashMap<String, int[]> meetingPoints;        // squad -> ponto de encontro (x,y)
    private ConcurrentHashMap<String, Set<String>> readyAgents;    // squad -> agentes prontos p/ connect
    private ConcurrentHashMap<String, String> collectorAssignments;// agente -> tipo de bloco atribuído
    private ConcurrentHashMap<String, String> squadActiveTask;     // squad -> tarefa ativa
    ConcurrentHashMap<String, Boolean> soloistBusy;        // agente -> ocupado? (pool de soloists)
    ConcurrentHashMap<String, int[]> agentPositions;       // agente -> última posição conhecida
    private ConcurrentHashMap<String, java.util.Set<String>> taskSoloist; // tarefa -> soloists (máx. 2)

    void init() {
        agentSquad = new ConcurrentHashMap<>();
        squadMembers = new ConcurrentHashMap<>();
        squadRole = new ConcurrentHashMap<>();
        meetingPoints = new ConcurrentHashMap<>();
        readyAgents = new ConcurrentHashMap<>();
        collectorAssignments = new ConcurrentHashMap<>();
        squadActiveTask = new ConcurrentHashMap<>();
        soloistBusy = new ConcurrentHashMap<>();
        agentPositions = new ConcurrentHashMap<>();
        taskSoloist = new ConcurrentHashMap<>();
        // taskSoloist maps task name → set of assigned agent names (max 2)
        setupDefaultSquads();
    }

    // Define a composição fixa: 4 squads (1 leader + 2 collectors +
    // 1 assembler cada) e 4 sentinels; todos entram no pool de soloists.
    private void setupDefaultSquads() {
        String[][] squads = {
            {"squad1", "connectionA1", "connectionA4", "connectionA5", "connectionA10"},
            {"squad2", "connectionA2", "connectionA6", "connectionA7", "connectionA11"},
            {"squad3", "connectionA3", "connectionA8", "connectionA9", "connectionA12"},
            {"squad4", "connectionA16", "connectionA17", "connectionA18", "connectionA19"}
        };
        String[][] roles = {
            {"connectionA1", "leader"}, {"connectionA2", "leader"}, {"connectionA3", "leader"},
            {"connectionA16", "leader"},
            {"connectionA4", "collector"}, {"connectionA5", "collector"},
            {"connectionA6", "collector"}, {"connectionA7", "collector"},
            {"connectionA8", "collector"}, {"connectionA9", "collector"},
            {"connectionA17", "collector"}, {"connectionA18", "collector"},
            {"connectionA10", "assembler"}, {"connectionA11", "assembler"}, {"connectionA12", "assembler"},
            {"connectionA19", "assembler"},
            {"connectionA13", "sentinel"}, {"connectionA14", "sentinel"}, {"connectionA15", "sentinel"},
            {"connectionA20", "sentinel"}
        };
        for (String[] sq : squads) {
            String sid = sq[0];
            List<String> members = new ArrayList<>();
            for (int i = 1; i < sq.length; i++) {
                agentSquad.put(sq[i], sid);
                members.add(sq[i]);
            }
            squadMembers.put(sid, members);
        }
        for (String[] r : roles) {
            squadRole.put(r[0], r[1]);
        }
        String[] soloists = {
            "connectionA1", "connectionA2", "connectionA3",
            "connectionA4", "connectionA5", "connectionA6", "connectionA7",
            "connectionA8", "connectionA9", "connectionA10", "connectionA11",
            "connectionA12", "connectionA13", "connectionA14", "connectionA15",
            "connectionA16", "connectionA17", "connectionA18", "connectionA19",
            "connectionA20"
        };
        for (String ag : soloists) {
            soloistBusy.put(ag, false);
        }
    }

    @OPERATION
    void get_my_squad(Object oagentName, OpFeedbackParam<String> squadId) {
        String ag = oagentName.toString();
        squadId.set(agentSquad.getOrDefault(ag, "none"));
    }

    @OPERATION
    void get_squad_collectors(Object osquadId,
                              OpFeedbackParam<String> col1,
                              OpFeedbackParam<String> col2) {
        String sid = osquadId.toString();
        List<String> members = squadMembers.getOrDefault(sid, Collections.emptyList());
        List<String> collectors = new ArrayList<>();
        for (String m : members) {
            if ("collector".equals(squadRole.get(m))) {
                collectors.add(m);
            }
        }
        col1.set(collectors.size() > 0 ? collectors.get(0) : "none");
        col2.set(collectors.size() > 1 ? collectors.get(1) : "none");
    }

    @OPERATION
    void get_squad_assembler(Object osquadId, OpFeedbackParam<String> assembler) {
        String sid = osquadId.toString();
        List<String> members = squadMembers.getOrDefault(sid, Collections.emptyList());
        for (String m : members) {
            if ("assembler".equals(squadRole.get(m))) {
                assembler.set(m);
                return;
            }
        }
        assembler.set("none");
    }

    @OPERATION
    void get_squad_leader(Object osquadId, OpFeedbackParam<String> leader) {
        String sid = osquadId.toString();
        List<String> members = squadMembers.getOrDefault(sid, Collections.emptyList());
        for (String m : members) {
            if ("leader".equals(squadRole.get(m))) {
                leader.set(m);
                return;
            }
        }
        leader.set("none");
    }

    // --- Coordenação multi-bloco: meeting point, prontidão e blocos ---

    // Define o ponto de encontro do squad (onde collector e assembler
    // se reúnem para o connect) e avisa os membros.
    @OPERATION
    void set_meeting_point(Object osquadId, Object ox, Object oy) {
        String sid = osquadId.toString();
        int x = toInt(ox), y = toInt(oy);
        meetingPoints.put(sid, new int[]{x, y});
        signal("meeting_point_set", sid, x, y);
    }

    @OPERATION
    void get_meeting_point(Object osquadId,
                           OpFeedbackParam<Integer> resX,
                           OpFeedbackParam<Integer> resY) {
        String sid = osquadId.toString();
        int[] mp = meetingPoints.get(sid);
        if (mp != null) {
            resX.set(mp[0]);
            resY.set(mp[1]);
        } else {
            resX.set(-1);
            resY.set(-1);
        }
    }

    @OPERATION
    void assign_block_to_collector(Object oagentName, Object oblockType) {
        String agName = oagentName.toString();
        String blockType = oblockType.toString();
        collectorAssignments.put(agName, blockType);
        signal("collect_order", agName, blockType);
    }

    @OPERATION
    void get_my_assignment(Object oagentName, OpFeedbackParam<String> blockType) {
        blockType.set(collectorAssignments.getOrDefault(oagentName.toString(), "none"));
    }

    @OPERATION
    void set_squad_task(Object osquadId, Object otaskName) {
        squadActiveTask.put(osquadId.toString(), otaskName.toString());
    }

    @OPERATION
    void get_squad_task(Object osquadId, OpFeedbackParam<String> taskName) {
        taskName.set(squadActiveTask.getOrDefault(osquadId.toString(), "none"));
    }

    @OPERATION
    void signal_ready(Object osquadId, Object oagentName) {
        String sid = osquadId.toString();
        String ag = oagentName.toString();
        readyAgents.computeIfAbsent(sid, k -> ConcurrentHashMap.newKeySet()).add(ag);
        signal("agent_ready", sid, ag);
    }

    // Verdadeiro só quando todos os collectors com bloco atribuído já
    // sinalizaram prontidão — gate para iniciar o connect sincronizado.
    @OPERATION
    void all_ready(Object osquadId, OpFeedbackParam<Boolean> result) {
        String sid = osquadId.toString();
        Set<String> ready = readyAgents.get(sid);
        List<String> collectors = new ArrayList<>();
        for (String m : squadMembers.getOrDefault(sid, Collections.emptyList())) {
            if ("collector".equals(squadRole.get(m)) && collectorAssignments.containsKey(m)) {
                collectors.add(m);
            }
        }
        int expected = collectors.size();
        if (expected == 0) { result.set(false); return; }
        int readyCount = 0;
        if (ready != null) {
            for (String c : collectors) {
                if (ready.contains(c)) readyCount++;
            }
        }
        result.set(readyCount >= expected);
    }

    @OPERATION
    void clear_ready(Object osquadId) {
        readyAgents.remove(osquadId.toString());
        String sid = osquadId.toString();
        List<String> members = squadMembers.getOrDefault(sid, Collections.emptyList());
        for (String m : members) {
            collectorAssignments.remove(m);
        }
    }

    // --- Pool universal de soloists ---

    @OPERATION
    void mark_busy(Object oagName) {            // agente assumiu uma tarefa
        soloistBusy.put(oagName.toString(), true);
    }

    @OPERATION
    void mark_free(Object oagName) {            // agente voltou ao pool
        soloistBusy.put(oagName.toString(), false);
    }

    @OPERATION
    void update_agent_pos(Object oagName, Object ox, Object oy) { // cache de posição p/ seleção
        agentPositions.put(oagName.toString(), new int[]{toInt(ox), toInt(oy)});
    }

    // Escolhe o soloist LIVRE mais próximo do dispenser (distância
    // Manhattan toroidal), minimizando o tempo de coleta.
    @OPERATION
    void find_free_soloist(Object odispX, Object odispY,
                           OpFeedbackParam<String> winner) {
        int dx = toInt(odispX), dy = toInt(odispY);
        String best = "none";
        int bestDist = Integer.MAX_VALUE;
        for (Map.Entry<String, Boolean> e : soloistBusy.entrySet()) {
            if (e.getValue()) continue;
            int[] pos = agentPositions.get(e.getKey());
            if (pos == null) continue;
            int dist = wrapDist(pos[0], dx, hive.GridConfig.width())
                     + wrapDist(pos[1], dy, hive.GridConfig.height());
            if (dist < bestDist) {
                bestDist = dist;
                best = e.getKey();
            }
        }
        winner.set(best);
    }

    @OPERATION
    void is_soloist_busy(Object oagName, OpFeedbackParam<Boolean> busy) {
        busy.set(soloistBusy.getOrDefault(oagName.toString(), false));
    }

    // Reivindica um "slot" de soloist para a tarefa (no máx. 2 agentes
    // por tarefa, suportando coleta de 2 blocos). Retorna se conseguiu.
    @OPERATION
    void claim_task_soloist(Object otaskName, Object oagName, OpFeedbackParam<Boolean> claimed) {
        String task = otaskName.toString();
        String agent = oagName.toString();
        java.util.Set<String> agents = taskSoloist.computeIfAbsent(task, k -> java.util.Collections.newSetFromMap(new ConcurrentHashMap<>()));
        if (agents.size() < 2) {
            agents.add(agent);
            claimed.set(true);
        } else {
            claimed.set(false);
        }
    }

    @OPERATION
    void release_task_soloist(Object otaskName) {
        taskSoloist.remove(otaskName.toString());
    }

    @OPERATION
    void release_agent_from_task(Object otaskName, Object oagName) {
        String task = otaskName.toString();
        String agent = oagName.toString();
        java.util.Set<String> agents = taskSoloist.get(task);
        if (agents != null) {
            agents.remove(agent);
            if (agents.isEmpty()) taskSoloist.remove(task);
        }
    }

    // package-private p/ teste; delega ao único helper de wrap toroidal (dedup — review PR #5)
    int wrapDist(int a, int b, int size) {
        return Math.abs(hive.AdjacentDirection.wrapDelta(b - a, size));
    }

    private int toInt(Object o) {
        if (o instanceof Number) return ((Number) o).intValue();
        return Integer.parseInt(o.toString());
    }
}
