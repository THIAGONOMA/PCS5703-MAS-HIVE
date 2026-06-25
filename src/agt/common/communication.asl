// ============================================================
// communication.asl — Mensagens de sincronizacao para connect
// ------------------------------------------------------------
// Troca de mensagens entre assembler e collector para combinar o
// connect multi-bloco: o assembler pede (request_connect), o collector
// registra um pending_connect e confirma (confirm_connect).
// No modo relativo (U9, absolutePosition:false) cada agente tem seu
// próprio quadro de coordenadas; por isso as coordenadas recebidas são
// traduzidas para o frame local usando known_offset (quando conhecido).
// ============================================================

// Assembler -> Collector: solicita connect informando sua posição e o
// step alvo em que ambos devem executar o connect simultaneamente.
+!request_connect(CollectorName, TargetStep)
    : my_pos(MX, MY)
    <- .my_name(Me);
       .send(CollectorName, tell, connect_request(Me, MX, MY, TargetStep));
       .print("[COMM] Pedido de connect enviado para ", CollectorName, " no step ", TargetStep).

// Collector recebe o pedido: traduz as coords do assembler para o seu
// frame (U9) e arma um pending_connect para o protocolo de connect.
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

// Collector -> Assembler: confirma prontidão e envia sua posição.
+!confirm_connect(AssemblerName)
    : my_pos(MX, MY)
    <- .my_name(Me);
       .send(AssemblerName, tell, connect_confirmed(Me, MX, MY));
       .print("[COMM] Confirmacao de connect enviada para ", AssemblerName).

// Assembler recebe a confirmação (também traduzindo coords via offset).
+connect_confirmed(CollectorName, ColX, ColY)[source(S)]
    <- if (known_offset(CollectorName, DX, DY)) {
           TCX = ColX + DX; TCY = ColY + DY
       } else {
           TCX = ColX; TCY = ColY
       };
       +partner_confirmed(CollectorName, TCX, TCY).

// Planos de fallback: se a posição não estiver disponível, não falha.
+!request_connect(_, _) <- true.
+!confirm_connect(_) <- true.
