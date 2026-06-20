// ============================================================
// role_adoption.asl — Adocao de role no cenario oficial (P0)
// ============================================================
// No oficial, 'default' NAO tem request/attach/connect/submit.
// Sem adotar 'worker' numa role zone, o time anda mas NUNCA pontua.
//
// Estrategia PROATIVA: no step 1, faz probe com attach(n). Se receber
// failed_role, sabe que esta no oficial e seta need_role_adoption
// imediatamente. No dev (default com todas as acoes) o probe retorna
// failed_target (sem dispenser ao lado) e o agente segue normalmente.
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

+step(N)
    : need_role_adoption & in_role_zone
    <- .abolish(role_nav_attempts(_));
       .abolish(role_nav_target(_, _));
       .print("[ROLE] Step ", N, ": em role zone, adotando worker");
       action("adopt(worker)").

// 2b) zona visivel nos percepts mas nao estamos nela — ir direto
//     Nao ir se ultimo move foi bloqueado (escape primeiro)
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

// 2c) escape reativo: se o ultimo move bloqueou, usar escape_move
+step(N)
    : need_role_adoption & my_pos(MX, MY) & has_destination(DX, DY)
      & (last_move_blocked | escape_pending(_, _))
    <- .abolish(last_move_blocked);
       .abolish(escape_pending(_, _));
       if (role_nav_attempts(RA)) {
           -role_nav_attempts(RA);
           +role_nav_attempts(RA + 1)
       } else {
           +role_nav_attempts(1)
       };
       !escape_move(MX, MY, DX, DY).

// 2d) timeout: se navega para mesma role zone por > 20 steps, blacklist
+step(N)
    : need_role_adoption & my_pos(MX, MY)
      & role_nav_attempts(RA) & RA > 20
      & role_nav_target(TX, TY)
    <- .print("[ROLE] Step ", N, ": TIMEOUT nav role zone (", TX, ",", TY, ") after ", RA, " attempts. Blacklisting.");
       remove_role_zone(TX, TY);
       .abolish(role_nav_attempts(_));
       .abolish(role_nav_target(_, _));
       .abolish(has_destination(_, _));
       !do_explore(MX, MY).

// 2e) navegar para role zone conhecida ou explorar
+step(N)
    : need_role_adoption & my_pos(MX, MY)
      & not last_move_blocked & not escape_pending(_, _)
    <- get_nearest_role_zone(MX, MY, RX, RY);
       if (RX \== -1 & not (RX == MX & RY == MY)) {
           if (role_nav_target(OTX, OTY) & OTX == RX & OTY == RY) {
               true
           } else {
               .abolish(role_nav_attempts(_));
               .abolish(role_nav_target(_, _));
               +role_nav_target(RX, RY);
               +role_nav_attempts(0)
           };
           if (role_nav_attempts(RA0)) {
               -role_nav_attempts(RA0);
               +role_nav_attempts(RA0 + 1)
           } else {
               +role_nav_attempts(1)
           };
           if ((N mod 50) == 0) {
               .print("[ROLE] Step ", N, ": nav role zone (", RX, ",", RY, ") from (", MX, ",", MY, ")")
           };
           .abolish(has_destination(_, _));
           +has_destination(RX, RY);
           compute_next_move(MX, MY, RX, RY, Dir);
           .abolish(last_attempted_dir(_));
           +last_attempted_dir(Dir);
           .concat("move(", Dir, ")", Act);
           action(Act)
       } elif (RX == MX & RY == MY) {
           remove_role_zone(RX, RY);
           !do_explore(MX, MY)
       } else {
           if ((N mod 100) == 0) {
               get_map_stats(V, D, G, R);
               .print("[ROLE] Step ", N, " vis=", V, " role=", R, " pos(", MX, ",", MY, ")")
           };
           !do_explore(MX, MY)
       }.
