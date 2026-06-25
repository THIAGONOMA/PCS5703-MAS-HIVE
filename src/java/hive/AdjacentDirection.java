package hive;

// ============================================================
// AdjacentDirection.java — Ação interna Jason hive.adjacent_direction
// ------------------------------------------------------------
// Dado (agX,agY), o alvo (tX,tY) e o tamanho do grid, devolve a direção
// cardinal (n/s/e/w) para um alvo ADJACENTE num grid toroidal, ou "none"
// se não for adjacente. Usada na navegação fina (ex.: encostar no
// dispenser/parceiro). A matemática de wrap toroidal (wrapDelta) é
// reutilizada por outros artefatos. Métodos estáticos = puros/testáveis.
// ============================================================

import jason.asSemantics.*;
import jason.asSyntax.*;

public class AdjacentDirection extends DefaultInternalAction {

    // Ponte AgentSpeak: lê os 4 inteiros, calcula a direção e unifica em args[4].
    @Override
    public Object execute(TransitionSystem ts, Unifier un, Term[] args)
            throws Exception {
        int agX = (int) ((NumberTerm) args[0]).solve();
        int agY = (int) ((NumberTerm) args[1]).solve();
        int tX  = (int) ((NumberTerm) args[2]).solve();
        int tY  = (int) ((NumberTerm) args[3]).solve();

        String dir = direction(agX, agY, tX, tY,
                               GridConfig.width(), GridConfig.height());

        return un.unifies(args[4], new Atom(dir));
    }

    /**
     * Direção adjacente (n/s/e/w) de (agX,agY) para (tX,tY) num grid toroidal
     * de tamanho w×h; "none" se não for adjacente (inclui origem==alvo).
     * Pura e testável (U4) — toda a matemática de wrap mora aqui.
     */
    public static String direction(int agX, int agY, int tX, int tY, int w, int h) {
        int dx = wrapDelta(tX - agX, w);
        int dy = wrapDelta(tY - agY, h);

        if (dx == 0 && dy == -1) return "n";
        if (dx == 0 && dy == 1)  return "s";
        if (dx == 1 && dy == 0)  return "e";
        if (dx == -1 && dy == 0) return "w";
        return "none";
    }

    /** Menor deslocamento com sentido num eixo toroidal de tamanho size. */
    public static int wrapDelta(int d, int size) {
        if (size <= 0) return d;
        if (d > size / 2) return d - size;
        if (d < -size / 2) return d + size;
        return d;
    }
}
