// ============================================================
// role_adoption.asl — Adocao de role no cenario oficial (P0)
// ============================================================
// No oficial, 'default' NAO tem request/attach/connect/submit.
// Sem adotar 'worker' numa role zone, o time anda mas NUNCA pontua.
//
// Estrategia SIMPLIFICADA para cave maze denso:
//   - Se role zone visivel na percepção (range ~5 cells), ir direto
//   - Senao, EXPLORAR. Nao navegar para role zones distantes conhecidas.
//   - Exploração com corridor-following encontra role zones naturalmente.
//
// Incluir ANTES de connect_protocol/collection/navigation.

role_capable(worker).
role_capable(constructor).

in_role_zone :- roleZone(0, 0).

// --- Probe proativo: detecta modo oficial no step 1 ---

+step(N)
    : N > 0 & not role_probe_done & not need_role_adoption
    <- +role_probe_done;
       .print("[ROLE] Step ", N, ": probe attach(n) para detectar modo");
       action("attach(n)").

// --- Step prioritario enquanto precisar adotar role ---

// 1) na role zone → adotar worker
+step(N)
    : need_role_adoption & in_role_zone
    <- .print("[ROLE] Step ", N, ": em role zone, adotando worker");
       action("adopt(worker)").

// 2) zona visivel nos percepts (range ≤ 5 cells) — ir direto
+step(N)
    : need_role_adoption & my_pos(MX, MY)
      & roleZone(VX, VY) & (VX \== 0 | VY \== 0)
      & not last_move_blocked & not escape_pending(_, _)
    <- GX = MX + VX; GY = MY + VY;
       .abolish(has_destination(_, _));
       +has_destination(GX, GY);
       compute_next_move(MX, MY, GX, GY, Dir);
       .abolish(last_attempted_dir(_));
       +last_attempted_dir(Dir);
       .concat("move(", Dir, ")", Act);
       action(Act).

// 3) escape reativo quando bloqueado navegando para role zone visivel
+step(N)
    : need_role_adoption & my_pos(MX, MY) & has_destination(DX, DY)
      & (last_move_blocked | escape_pending(_, _))
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       !escape_move(MX, MY, DX, DY).

// 4) fallback: explorar — encontrar role zones naturalmente
+step(N)
    : need_role_adoption & my_pos(MX, MY)
    <- if ((N mod 100) == 0) {
           get_map_stats(V, D, G, R);
           .print("[ROLE] Step ", N, " vis=", V, " role=", R, " pos(", MX, ",", MY, ")")
       };
       !do_explore(MX, MY).
