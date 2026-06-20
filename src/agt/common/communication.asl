// ============================================================
// communication.asl — Mensagens de sincronizacao para connect
// ============================================================
// U9: coords recebidas sao traduzidas via known_offset se disponivel.

+!request_connect(CollectorName, TargetStep)
    : my_pos(MX, MY)
    <- .my_name(Me);
       .send(CollectorName, tell, connect_request(Me, MX, MY, TargetStep));
       .print("[COMM] Pedido de connect enviado para ", CollectorName, " no step ", TargetStep).

+connect_request(AssemblerName, AsmX, AsmY, TargetStep)[source(S)]
    <- // U9: traduzir coords do assembler para meu frame
       if (known_offset(AssemblerName, DX, DY)) {
           TAX = AsmX + DX; TAY = AsmY + DY;
           .print("[COMM] connect_request de ", AssemblerName, " traduzido: (", AsmX, ",", AsmY, ")->(", TAX, ",", TAY, ")")
       } else {
           TAX = AsmX; TAY = AsmY
       };
       .abolish(navigating_to_meeting_point(_));
       .abolish(has_destination(_, _));
       +pending_connect(AssemblerName, TAX, TAY, TargetStep).

+!confirm_connect(AssemblerName)
    : my_pos(MX, MY)
    <- .my_name(Me);
       .send(AssemblerName, tell, connect_confirmed(Me, MX, MY));
       .print("[COMM] Confirmacao de connect enviada para ", AssemblerName).

+connect_confirmed(CollectorName, ColX, ColY)[source(S)]
    <- if (known_offset(CollectorName, DX, DY)) {
           TCX = ColX + DX; TCY = ColY + DY
       } else {
           TCX = ColX; TCY = ColY
       };
       +partner_confirmed(CollectorName, TCX, TCY).

+!request_connect(_, _) <- true.
+!confirm_connect(_) <- true.
