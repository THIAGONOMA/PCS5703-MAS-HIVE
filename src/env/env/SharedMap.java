package env;

import cartago.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

public class SharedMap extends Artifact {

    ConcurrentHashMap<String, String> cells;              // package-private p/ teste (Fase D / R7)
    Set<String> knownDispensers;                          // package-private p/ teste (Fase D / R7)
    Set<String> knownGoalZones;                           // package-private p/ teste (Fase D / R7)
    Set<String> knownRoleZones;                           // package-private p/ teste (Fase D / R7)
    Set<String> visitedCells;                             // package-private p/ teste (Fase D / R7)
    ConcurrentHashMap<String, Integer> obstacles;         // package-private p/ teste (backfill Track 1)
    ConcurrentHashMap<String, int[]> occupancy;           // nome -> {x, y, step}
    int occupancyStep = 0;                                // ultimo step reportado (p/ expirar entradas obsoletas)
    private static final int TEAMMATE_PENALTY = 16;
    int gridWidth = 0;
    int gridHeight = 0;
    private List<int[]> cachedFrontiers = new ArrayList<>();
    private int lastFrontierVisitedSize = -1;

    void init() {
        cells = new ConcurrentHashMap<>();
        knownDispensers = ConcurrentHashMap.newKeySet();
        knownGoalZones = ConcurrentHashMap.newKeySet();
        knownRoleZones = ConcurrentHashMap.newKeySet();
        visitedCells = ConcurrentHashMap.newKeySet();
        obstacles = new ConcurrentHashMap<>();
        occupancy = new ConcurrentHashMap<>();
    }

    @OPERATION
    void set_grid_dimensions(Object owidth, Object oheight) {
        gridWidth = toInt(owidth);
        gridHeight = toInt(oheight);
        hive.GridConfig.set(gridWidth, gridHeight);
    }

    /**
     * U4: define as dimensões a partir da fonte única hive.GridConfig
     * (default 40x40; override por -Dhive.grid.width/-Dhive.grid.height).
     */
    @OPERATION
    void apply_grid_config() {
        gridWidth = hive.GridConfig.width();
        gridHeight = hive.GridConfig.height();
    }

    private int norm(int v, int size) {
        if (size <= 0) return v;
        return ((v % size) + size) % size;
    }

    private int normX(int x) { return norm(x, gridWidth); }
    private int normY(int y) { return norm(y, gridHeight); }

    private String key(int x, int y) {
        return normX(x) + "," + normY(y);
    }

    private int wrapDist(int a, int b, int size) {
        if (size <= 0) return Math.abs(a - b);
        int d = Math.abs(norm(a, size) - norm(b, size));
        return Math.min(d, size - d);
    }

    private int wrappedManhattan(int x1, int y1, int x2, int y2) {
        return wrapDist(x1, x2, gridWidth) + wrapDist(y1, y2, gridHeight);
    }

    private int toInt(Object o) {
        if (o instanceof Number) return ((Number) o).intValue();
        return Integer.parseInt(o.toString());
    }

    @OPERATION
    void update_cell(Object ox, Object oy, Object otype, Object odetails) {
        int x = normX(toInt(ox));
        int y = normY(toInt(oy));
        String type = otype.toString();
        String details = odetails.toString();
        String k = x + "," + y;
        cells.put(k, type + ":" + details);
        visitedCells.add(k);

        if (type.equals("dispenser")) {
            String dispKey = k + ":" + details;
            if (knownDispensers.add(dispKey)) {
                defineObsProperty("known_dispenser", x, y, details);
                signal("new_dispenser", x, y, details);
            }
        } else if (type.equals("goal_zone")) {
            if (knownGoalZones.add(k)) {
                defineObsProperty("known_goal_zone", x, y);
                signal("new_goal_zone", x, y);
            }
        } else if (type.equals("role_zone")) {
            if (knownRoleZones.add(k)) {
                defineObsProperty("known_role_zone", x, y);
                signal("new_role_zone", x, y);
            }
        }
    }

    @OPERATION
    void remove_role_zone(Object ox, Object oy) {
        String k = toInt(ox) + "," + toInt(oy);
        knownRoleZones.remove(k);
    }

    @OPERATION
    void mark_visited(Object ox, Object oy) {
        String k = key(toInt(ox), toInt(oy));
        visitedCells.add(k);
        obstacles.remove(k);
    }

    // #49/N2: marca todas as células no raio de visão como visitadas.
    // Sem isso, só cells com things entram em visitedCells, deixando fronteiras
    // esparsas e a exploração lenta (agente volta a áreas "desconhecidas" que já viu).
    @OPERATION
    void mark_vision_visited(Object ox, Object oy, Object ovision) {
        int cx = toInt(ox), cy = toInt(oy), vis = toInt(ovision);
        for (int dx = -vis; dx <= vis; dx++) {
            for (int dy = -vis; dy <= vis; dy++) {
                if (Math.abs(dx) + Math.abs(dy) > vis) continue;
                String k = key(cx + dx, cy + dy);
                if (!obstacles.containsKey(k)) {
                    visitedCells.add(k);
                }
            }
        }
    }

    @OPERATION
    void get_nearest_dispenser(Object oagX, Object oagY, Object otype,
                               OpFeedbackParam<Integer> resX,
                               OpFeedbackParam<Integer> resY) {
        int agX = normX(toInt(oagX)), agY = normY(toInt(oagY));
        String type = otype.toString();
        int bestCost = Integer.MAX_VALUE;
        int bx = -1, by = -1;

        int nearestGoalX = -1, nearestGoalY = -1;
        int bestGoalDist = Integer.MAX_VALUE;
        for (String gk : knownGoalZones) {
            String[] gp = gk.split(",");
            int gx = Integer.parseInt(gp[0]), gy = Integer.parseInt(gp[1]);
            int gd = wrappedManhattan(gx, gy, agX, agY);
            if (gd < bestGoalDist) { bestGoalDist = gd; nearestGoalX = gx; nearestGoalY = gy; }
        }

        for (String dispKey : knownDispensers) {
            String[] parts = dispKey.split("[:,]");
            if (parts.length >= 3 && parts[2].equals(type)) {
                int dx = Integer.parseInt(parts[0]);
                int dy = Integer.parseInt(parts[1]);
                int costToDisp = wrappedManhattan(dx, dy, agX, agY);
                int costDispToGoal = 0;
                if (nearestGoalX != -1) {
                    costDispToGoal = wrappedManhattan(dx, dy, nearestGoalX, nearestGoalY);
                }
                int totalCost = costToDisp + costDispToGoal;
                if (totalCost < bestCost) {
                    bestCost = totalCost;
                    bx = dx;
                    by = dy;
                }
            }
        }
        resX.set(bx);
        resY.set(by);
    }

    @OPERATION
    void get_nearest_goal_zone(Object oagX, Object oagY,
                               OpFeedbackParam<Integer> resX,
                               OpFeedbackParam<Integer> resY) {
        int agX = normX(toInt(oagX)), agY = normY(toInt(oagY));
        int bestDist = Integer.MAX_VALUE;
        int bx = -1, by = -1;

        for (String k : knownGoalZones) {
            String[] parts = k.split(",");
            int gx = Integer.parseInt(parts[0]);
            int gy = Integer.parseInt(parts[1]);
            int pathCost = astarCost(agX, agY, gx, gy);
            if (pathCost < bestDist) {
                bestDist = pathCost;
                bx = gx;
                by = gy;
            }
        }
        resX.set(bx);
        resY.set(by);
    }

    // P0 (cenario oficial): role zone mais proxima (custo A*) para o agente ir
    // adotar 'worker'/'constructor'. Espelha get_nearest_goal_zone. -1 se nenhuma.
    @OPERATION
    void get_nearest_role_zone(Object oagX, Object oagY,
                               OpFeedbackParam<Integer> resX,
                               OpFeedbackParam<Integer> resY) {
        int agX = normX(toInt(oagX)), agY = normY(toInt(oagY));
        int bestDist = Integer.MAX_VALUE;
        int bx = -1, by = -1;
        for (String k : knownRoleZones) {
            String[] parts = k.split(",");
            int gx = Integer.parseInt(parts[0]);
            int gy = Integer.parseInt(parts[1]);
            int pathCost = astarCost(agX, agY, gx, gy);
            if (pathCost < bestDist) {
                bestDist = pathCost;
                bx = gx;
                by = gy;
            }
        }
        resX.set(bx);
        resY.set(by);
    }

    @OPERATION
    void get_alternative_goal_zone(Object oagX, Object oagY, Object ocurX, Object ocurY,
                                   OpFeedbackParam<Integer> resX,
                                   OpFeedbackParam<Integer> resY) {
        int agX = normX(toInt(oagX)), agY = normY(toInt(oagY));
        int curX = normX(toInt(ocurX)), curY = normY(toInt(ocurY));
        String curKey = curX + "," + curY;
        int bestDist = Integer.MAX_VALUE;
        int bx = -1, by = -1;
        for (String k : knownGoalZones) {
            if (k.equals(curKey)) continue;
            String[] parts = k.split(",");
            int gx = Integer.parseInt(parts[0]);
            int gy = Integer.parseInt(parts[1]);
            int dist = astarCost(agX, agY, gx, gy);
            if (dist < bestDist) {
                bestDist = dist;
                bx = gx;
                by = gy;
            }
        }
        if (bx == -1) { bx = curX; by = curY; }
        resX.set(bx);
        resY.set(by);
    }

    private void rebuildFrontierCache() {
        List<int[]> result = new ArrayList<>();
        int[][] dirs = {{0,1},{0,-1},{1,0},{-1,0}};
        Set<String> seen = new HashSet<>();
        for (String visited : visitedCells) {
            String[] parts = visited.split(",");
            int vx = Integer.parseInt(parts[0]);
            int vy = Integer.parseInt(parts[1]);
            for (int[] d : dirs) {
                int nx = normX(vx + d[0]);
                int ny = normY(vy + d[1]);
                String nk = nx + "," + ny;
                if (!visitedCells.contains(nk) && !seen.contains(nk)
                        && !obstacles.containsKey(nk)) {
                    String cellContent = cells.get(nk);
                    if (cellContent == null || !cellContent.startsWith("obstacle")) {
                        result.add(new int[]{nx, ny});
                        seen.add(nk);
                    }
                }
            }
        }
        cachedFrontiers = result;
    }

    @OPERATION
    void get_nearest_frontier(Object oagX, Object oagY,
                              OpFeedbackParam<Integer> resX,
                              OpFeedbackParam<Integer> resY) {
        int agX = normX(toInt(oagX)), agY = normY(toInt(oagY));
        int vSize = visitedCells.size();
        if (cachedFrontiers.isEmpty() || Math.abs(vSize - lastFrontierVisitedSize) >= 3) {
            rebuildFrontierCache();
            lastFrontierVisitedSize = vSize;
        }

        int bestDist = Integer.MAX_VALUE;
        int bx = agX, by = agY;
        for (int[] f : cachedFrontiers) {
            int dist = wrappedManhattan(f[0], f[1], agX, agY);
            if (dist < bestDist) {
                bestDist = dist;
                bx = f[0];
                by = f[1];
            }
        }
        resX.set(bx);
        resY.set(by);
    }

    // #49/N2: direção de exploração por agente — distribui agentes radialmente.
    @OPERATION
    void get_sector_target(Object oAgentName, Object oTotalAgents,
                           OpFeedbackParam<Integer> resX, OpFeedbackParam<Integer> resY) {
        String name = oAgentName.toString();
        int index = Integer.parseInt(name.replaceAll("[^0-9]", ""));
        int total = Math.max(1, toInt(oTotalAgents));
        double angle = (2.0 * Math.PI * (index - 1)) / total;
        int radius = 20;
        resX.set((int) Math.round(radius * Math.cos(angle)));
        resY.set((int) Math.round(radius * Math.sin(angle)));
    }

    // #49/N2: fronteira biased pela direção do setor. Em vez de ir ao frontier mais
    // próximo (clustering), vai ao que melhor alinha com a direção atribuída ao agente.
    // Fronteiras são adjacentes a células visitadas → reachable, evita failed_path.
    @OPERATION
    void get_directional_frontier(Object oAgX, Object oAgY, Object oDirX, Object oDirY,
                                  OpFeedbackParam<Integer> resX, OpFeedbackParam<Integer> resY) {
        int agX = toInt(oAgX), agY = toInt(oAgY);
        int dirX = toInt(oDirX), dirY = toInt(oDirY);

        int vSize = visitedCells.size();
        if (cachedFrontiers.isEmpty() || Math.abs(vSize - lastFrontierVisitedSize) >= 3) {
            rebuildFrontierCache();
            lastFrontierVisitedSize = vSize;
        }

        double bestScore = Double.NEGATIVE_INFINITY;
        int bx = agX, by = agY;
        double dirLen = Math.sqrt((double) dirX * dirX + (double) dirY * dirY);
        if (dirLen < 1.0) dirLen = 1.0;

        for (int[] f : cachedFrontiers) {
            int dx = f[0] - agX, dy = f[1] - agY;
            int dist = wrappedManhattan(agX, agY, f[0], f[1]);
            if (dist == 0) continue;
            double dot = (dx * dirX + dy * dirY) / dirLen;
            double score = dot * 3.0 - dist;
            if (score > bestScore) {
                bestScore = score;
                bx = f[0]; by = f[1];
            }
        }
        resX.set(bx);
        resY.set(by);
    }

    @OPERATION
    void get_map_stats(OpFeedbackParam<Integer> totalVisited,
                       OpFeedbackParam<Integer> totalDispensers,
                       OpFeedbackParam<Integer> totalGoalZones,
                       OpFeedbackParam<Integer> totalRoleZones) {
        totalVisited.set(visitedCells.size());
        totalDispensers.set(knownDispensers.size());
        totalGoalZones.set(knownGoalZones.size());
        totalRoleZones.set(knownRoleZones.size());
    }

    @OPERATION
    void mark_obstacle(Object ox, Object oy, Object ostep) {
        String k = key(toInt(ox), toInt(oy));
        if (obstacles.containsKey(k)) return;
        obstacles.put(k, toInt(ostep));
    }

    @OPERATION
    void decay_obstacles(Object ostep) {
        int step = toInt(ostep);
        if (step % 5 != 0) return;
        obstacles.entrySet().removeIf(e -> e.getValue() < step - 30);
        // Fase D (#7): poda entradas de ocupacao 'seen_' obsoletas. O astar so usa
        // as do ultimo step (gate occupancyStep-1, linha ~358); as velhas so ocupam
        // memoria e crescem monotonicamente. Entradas de posicao de agente (chave =
        // nome do agente) NAO sao podadas aqui — expiram pelo proprio gate.
        occupancy.entrySet().removeIf(
            e -> e.getKey().startsWith("seen_") && e.getValue()[2] < occupancyStep - 1);
    }

    @OPERATION
    void compute_next_move(Object ofx, Object ofy, Object otx, Object oty,
                           OpFeedbackParam<String> dir) {
        int fx = normX(toInt(ofx)), fy = normY(toInt(ofy));
        int tx = normX(toInt(otx)), ty = normY(toInt(oty));
        if (fx == tx && fy == ty) { dir.set("skip"); return; }

        dir.set(astar(fx, fy, tx, ty));
    }

    @OPERATION
    void manhattan_dist(Object ox1, Object oy1, Object ox2, Object oy2,
                        OpFeedbackParam<Integer> dist) {
        dist.set(wrappedManhattan(toInt(ox1), toInt(oy1), toInt(ox2), toInt(oy2)));
    }

    // #2: indice de ocupacao viva (overlay efemero do A*). Cada agente empurra
    // sua posicao por step (ao lado de update_agent_pos no SquadCoordinator);
    // o astar penaliza essas celulas. Sobrescreve (sem decay).
    @OPERATION
    void update_occupancy(Object oName, Object ox, Object oy, Object ostep) {
        int s = toInt(ostep);
        occupancy.put(oName.toString(), new int[]{normX(toInt(ox)), normY(toInt(oy)), s});
        if (s > occupancyStep) occupancyStep = s;
    }

    private Set<String> buildBlocked(int fx, int fy, int tx, int ty) {
        Set<String> blocked = new HashSet<>(obstacles.keySet());
        if (cells != null) {
            for (Map.Entry<String, String> e : cells.entrySet()) {
                if (e.getValue().startsWith("obstacle")) blocked.add(e.getKey());
            }
        }
        blocked.remove(tx + "," + ty);
        blocked.remove(fx + "," + fy);
        return blocked;
    }

    private int astarCost(int fx, int fy, int tx, int ty) {
        fx = normX(fx); fy = normY(fy);
        tx = normX(tx); ty = normY(ty);
        int mDist = wrappedManhattan(fx, fy, tx, ty);
        if (mDist > 60) return mDist;

        Set<String> blocked = buildBlocked(fx, fy, tx, ty);
        int[][] dirs = {{0,-1},{0,1},{-1,0},{1,0}};

        PriorityQueue<int[]> open = new PriorityQueue<>(Comparator.comparingInt(a -> a[2]));
        Set<String> closed = new HashSet<>();
        Map<String, Integer> gScore = new HashMap<>();

        String startKey = fx + "," + fy;
        gScore.put(startKey, 0);
        open.add(new int[]{fx, fy, mDist});

        while (!open.isEmpty() && closed.size() < 3000) {
            int[] cur = open.poll();
            int cx = cur[0], cy = cur[1];
            String ck = cx + "," + cy;
            if (closed.contains(ck)) continue;
            closed.add(ck);
            if (cx == tx && cy == ty) return gScore.get(ck);

            int cg = gScore.get(ck);
            for (int[] d : dirs) {
                int nx = normX(cx + d[0]);
                int ny = normY(cy + d[1]);
                String nk = nx + "," + ny;
                if (blocked.contains(nk) || closed.contains(nk)) continue;
                int ng = cg + 1;
                if (ng < gScore.getOrDefault(nk, Integer.MAX_VALUE)) {
                    gScore.put(nk, ng);
                    open.add(new int[]{nx, ny, ng + wrappedManhattan(tx, ty, nx, ny)});
                }
            }
        }
        return mDist * 3;
    }

    String astar(int fx, int fy, int tx, int ty) {   // package-private p/ teste (backfill Track 1)
        fx = normX(fx); fy = normY(fy);
        tx = normX(tx); ty = normY(ty);
        int mDist = wrappedManhattan(fx, fy, tx, ty);
        if (mDist > 60) return greedy(fx, fy, tx, ty);

        Set<String> blocked = buildBlocked(fx, fy, tx, ty);
        // #2: overlay de ocupacao viva — penaliza (nao bloqueia) celula de colega,
        // exceto origem e alvo. So no astar (escolha do passo), nao no astarCost.
        Set<String> occupied = new HashSet<>();
        for (int[] p : occupancy.values()) {
            if (p[2] >= occupancyStep - 1) {   // #1: so posicoes frescas; entrada de agente desconectado expira (step congelado)
                occupied.add(p[0] + "," + p[1]);
            }
        }
        occupied.remove(tx + "," + ty);
        occupied.remove(fx + "," + fy);
        int[][] dirs = {{0,-1},{0,1},{-1,0},{1,0}};

        PriorityQueue<int[]> open = new PriorityQueue<>(Comparator.comparingInt(a -> a[2]));
        Set<String> closed = new HashSet<>();
        Map<String, String> cameFrom = new HashMap<>();
        Map<String, Integer> gScore = new HashMap<>();

        String startKey = fx + "," + fy;
        gScore.put(startKey, 0);
        open.add(new int[]{fx, fy, mDist});

        while (!open.isEmpty() && closed.size() < 8000) {
            int[] cur = open.poll();
            int cx = cur[0], cy = cur[1];
            String ck = cx + "," + cy;

            if (closed.contains(ck)) continue;
            closed.add(ck);

            if (cx == tx && cy == ty) {
                String step = ck;
                while (cameFrom.containsKey(step) && !cameFrom.get(step).equals(startKey)) {
                    step = cameFrom.get(step);
                }
                if (!cameFrom.containsKey(step)) step = ck;
                String[] parts = step.split(",");
                int sx = Integer.parseInt(parts[0]), sy = Integer.parseInt(parts[1]);
                int ddx = sx - fx, ddy = sy - fy;
                if (gridWidth > 0 && Math.abs(ddx) > gridWidth / 2) {
                    ddx = ddx > 0 ? ddx - gridWidth : ddx + gridWidth;
                }
                if (gridHeight > 0 && Math.abs(ddy) > gridHeight / 2) {
                    ddy = ddy > 0 ? ddy - gridHeight : ddy + gridHeight;
                }
                if (ddx == 0 && ddy == -1) return "n";
                if (ddx == 0 && ddy == 1)  return "s";
                if (ddx == -1 && ddy == 0) return "w";
                if (ddx == 1 && ddy == 0)  return "e";
                return greedy(fx, fy, tx, ty);
            }

            int cg = gScore.get(ck);
            for (int i = 0; i < 4; i++) {
                int nx = normX(cx + dirs[i][0]);
                int ny = normY(cy + dirs[i][1]);
                String nk = nx + "," + ny;
                if (blocked.contains(nk) || closed.contains(nk)) continue;
                int ng = cg + 1 + (occupied.contains(nk) ? TEAMMATE_PENALTY : 0);
                if (ng < gScore.getOrDefault(nk, Integer.MAX_VALUE)) {
                    gScore.put(nk, ng);
                    cameFrom.put(nk, ck);
                    int f = ng + wrappedManhattan(tx, ty, nx, ny);
                    open.add(new int[]{nx, ny, f});
                }
            }
        }
        return greedy(fx, fy, tx, ty);
    }

    private String greedy(int fx, int fy, int tx, int ty) {
        fx = normX(fx); fy = normY(fy);
        tx = normX(tx); ty = normY(ty);
        int dx, dy;
        if (gridWidth > 0) {
            int rawDx = tx - fx;
            int absDx = Math.abs(rawDx);
            dx = (absDx <= gridWidth - absDx) ? rawDx : (rawDx > 0 ? rawDx - gridWidth : rawDx + gridWidth);
        } else {
            dx = tx - fx;
        }
        if (gridHeight > 0) {
            int rawDy = ty - fy;
            int absDy = Math.abs(rawDy);
            dy = (absDy <= gridHeight - absDy) ? rawDy : (rawDy > 0 ? rawDy - gridHeight : rawDy + gridHeight);
        } else {
            dy = ty - fy;
        }
        if (Math.abs(dx) >= Math.abs(dy)) {
            return dx > 0 ? "e" : "w";
        }
        return dy > 0 ? "s" : "n";
    }

    // ===== Fase D / R7: costura de traducao de frame =====
    // Re-keia todo o estado por-celula deste mapa por um offset (dX,dY), traduzindo
    // este frame para outro (toroidalmente, com as dims correntes). Inerte no
    // incremento 1 (nenhuma fusao chama); existe para a fusao cross-agente (U9)
    // entrar como camada de traducao SEM reescrever o mapa, e e exercitada em teste
    // (prova que o mapa por-agente e parametrizado por frame). Nao re-emite obs
    // properties (known_*) — isso fica para a U9.
    // #9 (review): translateCells NAO e @OPERATION (e metodo puro, chamado so em teste).
    // Quando a U9 a invocar a partir de .asl, ela DEVE ser embrulhada num @OPERATION
    // (ex.: merge_frame(dX,dY)) — senao fica invisivel aos agentes/CArtAgO.
    private String shiftKey(String key, int dX, int dY) {
        int ci = key.indexOf(',');
        int x = Integer.parseInt(key.substring(0, ci));
        int y = Integer.parseInt(key.substring(ci + 1));
        return normX(x + dX) + "," + normY(y + dY);
    }

    private Set<String> shiftKeySet(Set<String> in, int dX, int dY) {
        Set<String> out = ConcurrentHashMap.newKeySet();
        for (String k : in) out.add(shiftKey(k, dX, dY));
        return out;
    }

    private Set<String> shiftDispensers(Set<String> in, int dX, int dY) {
        Set<String> out = ConcurrentHashMap.newKeySet();
        for (String k : in) {
            int ci = k.indexOf(',');
            int co = k.indexOf(':');
            int x = Integer.parseInt(k.substring(0, ci));
            int y = Integer.parseInt(k.substring(ci + 1, co));
            String details = k.substring(co + 1);
            out.add(normX(x + dX) + "," + normY(y + dY) + ":" + details);
        }
        return out;
    }

    void translateCells(int dX, int dY) {
        ConcurrentHashMap<String, String> nc = new ConcurrentHashMap<>();
        for (Map.Entry<String, String> e : cells.entrySet()) {
            nc.put(shiftKey(e.getKey(), dX, dY), e.getValue());
        }
        cells = nc;

        ConcurrentHashMap<String, Integer> no = new ConcurrentHashMap<>();
        for (Map.Entry<String, Integer> e : obstacles.entrySet()) {
            no.put(shiftKey(e.getKey(), dX, dY), e.getValue());
        }
        obstacles = no;

        visitedCells = shiftKeySet(visitedCells, dX, dY);
        knownGoalZones = shiftKeySet(knownGoalZones, dX, dY);
        knownRoleZones = shiftKeySet(knownRoleZones, dX, dY);
        knownDispensers = shiftDispensers(knownDispensers, dX, dY);

        for (int[] p : occupancy.values()) {
            p[0] = normX(p[0] + dX);
            p[1] = normY(p[1] + dY);
        }

        // Fase D (#9): as fronteiras em cache estao no frame antigo — invalida p/
        // forcar recomputo no novo frame. (As obs properties known_* tambem ficam
        // stale; re-emiti-las exige estar dentro de um @OPERATION e fica para a U9,
        // quando translateCells ganhar um chamador real — ver comentario acima.)
        cachedFrontiers = new ArrayList<>();
        lastFrontierVisitedSize = -1;
    }

    // ===== U9: Import/Export de discoveries para fusão de mapas =====

    @OPERATION
    void import_dispenser(Object ox, Object oy, Object otype) {
        int x = normX(toInt(ox));
        int y = normY(toInt(oy));
        String type = otype.toString();
        String k = x + "," + y;
        String dispKey = k + ":" + type;
        if (knownDispensers.add(dispKey)) {
            cells.put(k, "dispenser:" + type);
            defineObsProperty("known_dispenser", x, y, type);
        }
    }

    @OPERATION
    void import_goal_zone(Object ox, Object oy) {
        int x = normX(toInt(ox));
        int y = normY(toInt(oy));
        String k = x + "," + y;
        if (knownGoalZones.add(k)) {
            cells.put(k, "goal_zone:");
            defineObsProperty("known_goal_zone", x, y);
        }
    }

    @OPERATION
    void import_role_zone(Object ox, Object oy) {
        int x = normX(toInt(ox));
        int y = normY(toInt(oy));
        String k = x + "," + y;
        if (knownRoleZones.add(k)) {
            cells.put(k, "role_zone:");
            defineObsProperty("known_role_zone", x, y);
        }
    }

    @OPERATION
    void get_discovery_counts(OpFeedbackParam<Integer> nDisp,
                              OpFeedbackParam<Integer> nGoal,
                              OpFeedbackParam<Integer> nRole) {
        nDisp.set(knownDispensers.size());
        nGoal.set(knownGoalZones.size());
        nRole.set(knownRoleZones.size());
    }

    @OPERATION
    void export_dispensers(OpFeedbackParam<Object[]> result) {
        Object[] arr = knownDispensers.toArray();
        result.set(arr);
    }

    @OPERATION
    void export_goal_zones(OpFeedbackParam<Object[]> result) {
        Object[] arr = knownGoalZones.toArray();
        result.set(arr);
    }

    @OPERATION
    void export_role_zones(OpFeedbackParam<Object[]> result) {
        Object[] arr = knownRoleZones.toArray();
        result.set(arr);
    }
}
