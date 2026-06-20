package connection;

import java.util.ArrayList;
import java.util.HashSet;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

import cartago.Artifact;
import cartago.INTERNAL_OPERATION;
import cartago.OPERATION;
import cartago.ObsProperty;
import eis.AgentListener;
import eis.PerceptUpdate;
import eis.exceptions.AgentException;
import eis.exceptions.ManagementException;
import eis.exceptions.RelationException;
import eis.iilang.Action;
import eis.iilang.Percept;
import jason.asSyntax.Literal;
import massim.eismassim.EnvironmentInterface;

public class EISAccess extends Artifact implements AgentListener {

    private static EnvironmentInterface sharedEI;
    private static boolean eisStarted = false;
    private static final Object lock = new Object();

    private String agName = "";
    private boolean receiving = false;
    private int awaitTime = 500;
    private String lastStep = "-1";
    private List<ObsProperty> lastRoundProperties = new ArrayList<>();

    private Set<String> currentPerceptKeys = new LinkedHashSet<>();
    private List<Percept> currentPercepts = new ArrayList<>();
    private boolean firstStep = true;

    private int drX = 0, drY = 0;
    private String pendingMoveDir = null;
    private boolean hasPosition = false;

    private static final Set<String> SIM_START_PERCEPTS = new HashSet<>();
    static {
        SIM_START_PERCEPTS.add("simStart");
        SIM_START_PERCEPTS.add("requestAction");
        SIM_START_PERCEPTS.add("steps");
        SIM_START_PERCEPTS.add("name");
        SIM_START_PERCEPTS.add("team");
        SIM_START_PERCEPTS.add("teamSize");
    }

    void init(String conf, String entityName) {
        this.agName = entityName;
        System.out.println("[EISAccess] init called for agent: " + entityName + " conf: " + conf);

        synchronized (lock) {
            if (!eisStarted) {
                System.out.println("[EISAccess] Creating shared EnvironmentInterface from: " + conf);
                sharedEI = new EnvironmentInterface(conf);
                try {
                    sharedEI.start();
                    System.out.println("[EISAccess] EnvironmentInterface started successfully");
                } catch (ManagementException e) {
                    System.err.println("[EISAccess] ERROR starting EnvironmentInterface:");
                    e.printStackTrace();
                }
                eisStarted = true;
            }
        }

        try {
            sharedEI.registerAgent(this.agName);
            System.out.println("[EISAccess] Registered agent: " + this.agName);
        } catch (AgentException e) {
            System.err.println("[EISAccess] ERROR registering agent " + this.agName + ":");
            e.printStackTrace();
        }

        sharedEI.attachAgentListener(this.agName, this);

        try {
            sharedEI.associateEntity(this.agName, this.agName);
            System.out.println("[EISAccess] Associated entity: " + this.agName);
        } catch (RelationException e) {
            System.err.println("[EISAccess] ERROR associating entity " + this.agName + ":");
            e.printStackTrace();
        }

        this.receiving = true;
        execInternalOp("updatePercepts");
    }

    private String perceptKey(Percept p) {
        return p.toProlog();
    }

    @INTERNAL_OPERATION
    void updatePercepts() {
        while (this.receiving) {
            try {
                Map<String, PerceptUpdate> updates = sharedEI.getPercepts(this.agName);
                PerceptUpdate pu = updates.get(this.agName);
                if (pu == null || pu.isEmpty()) {
                    await_time(this.awaitTime);
                    continue;
                }

                List<Percept> addList = pu.getAddList();
                boolean newStep = false;
                for (Percept pe : addList) {
                    if (pe.getName().equals("step")) {
                        String stepVal = pe.getParameters().get(0).toString();
                        if (!stepVal.equals(this.lastStep)) {
                            this.lastStep = stepVal;
                            newStep = true;
                        }
                        break;
                    }
                }

                if (newStep) {
                    List<Percept> delList = pu.getDeleteList();
                    for (Percept del : delList) {
                        String key = perceptKey(del);
                        if (currentPerceptKeys.remove(key)) {
                            currentPercepts.removeIf(p -> perceptKey(p).equals(key));
                        }
                    }
                    for (Percept add : addList) {
                        String key = perceptKey(add);
                        if (currentPerceptKeys.add(key)) {
                            currentPercepts.add(add);
                        }
                    }

                    // DR: check result and update position BEFORE exposing percepts
                    String actionResult = null;
                    boolean hasAbsPosition = false;
                    for (Percept pe : currentPercepts) {
                        if (pe.getName().equals("lastActionResult")) {
                            actionResult = pe.getParameters().get(0).toString();
                        } else if (pe.getName().equals("position")) {
                            hasAbsPosition = true;
                        }
                    }
                    if (hasAbsPosition) {
                        hasPosition = true;
                    }
                    if (!hasPosition && pendingMoveDir != null && "success".equals(actionResult)) {
                        switch (pendingMoveDir) {
                            case "n": drY--; break;
                            case "s": drY++; break;
                            case "e": drX++; break;
                            case "w": drX--; break;
                        }
                    }
                    pendingMoveDir = null;

                    clearPercepts();

                    // Expose DR position as observable property (before step)
                    if (!hasPosition) {
                        this.lastRoundProperties.add(defineObsProperty("dr_pos", drX, drY));
                    }

                    Percept step = null;
                    for (Percept pe : currentPercepts) {
                        String pName = pe.getName();
                        if (pName.equals("step")) {
                            step = pe;
                            continue;
                        }
                        if (!firstStep && SIM_START_PERCEPTS.contains(pName)) {
                            continue;
                        }
                        try {
                            this.lastRoundProperties.add(defineObsProperty(pName,
                                    (Object[]) Translator.parametersToTerms(pe.getClonedParameters())));
                        } catch (Exception e) {
                            // skip
                        }
                    }
                    if (step != null) {
                        this.lastRoundProperties.add(defineObsProperty(step.getName(),
                                (Object[]) Translator.parametersToTerms(step.getClonedParameters())));
                    }
                    firstStep = false;
                }
            } catch (IllegalMonitorStateException imse) {
                // EISMASSim threading issue — retry silently
            } catch (Exception e) {
                // retry
            }
            await_time(this.awaitTime);
        }
    }

    private void clearPercepts() {
        for (ObsProperty obs : this.lastRoundProperties) {
            try {
                removeObsProperty(obs.getName());
            } catch (Exception e) {
                // already removed
            }
        }
        this.lastRoundProperties.clear();
    }

    @OPERATION
    void action(String action) {
        Literal literal = Literal.parseLiteral(action);
        // Track move direction for DR
        if (action.startsWith("move(")) {
            String dir = action.substring(5, action.length() - 1);
            if (dir.equals("n") || dir.equals("s") || dir.equals("e") || dir.equals("w")) {
                pendingMoveDir = dir;
            } else {
                pendingMoveDir = null;
            }
        } else {
            pendingMoveDir = null;
        }
        int retries = 3;
        for (int i = 0; i < retries; i++) {
            try {
                if (sharedEI != null) {
                    Action a = Translator.literalToAction(literal);
                    sharedEI.performAction(this.agName, a);
                    return;
                }
            } catch (Exception e) {
                Throwable cause = e.getCause();
                if (cause == null) cause = e;
                if (cause instanceof IllegalMonitorStateException) {
                    try { Thread.sleep(20); } catch (InterruptedException ie) { break; }
                } else {
                    return;
                }
            }
        }
    }

    @Override
    public void handlePercept(String agent, Percept percept) {
    }
}
