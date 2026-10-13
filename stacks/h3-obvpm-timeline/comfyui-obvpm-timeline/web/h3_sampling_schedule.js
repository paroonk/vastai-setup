// H3 Sampling Schedule: while a bundle is wired to `settings`, hide the
// widgets it replaces -- the server then reads the schedule from the bundle
// alone, so changing them would do nothing.
//
// Which widgets those are comes from the server, on the settings input's
// options (obvpm_replaces = nodes_stages._FROM_SETTINGS), so the list lives
// in one place. width and height are not among them: they stay the node's.
//
// Those widgets have NO sockets: a hidden widget keeps the last y it was
// laid out at, and its socket with it -- invisible but still hit-tested
// over the pins below (clicking `width` grabbed the hidden `scheduler`).
// `settings` is how the schedule is wired, so their unlinked sockets are
// dropped once, when the node is made or loaded; a workflow that wired
// them one by one keeps its links.
//
// A loaded node keeps the size it was saved with (its rows were saved
// matching); only wiring or unwiring `settings` by hand refits the height.
//
// The outputs were reordered in 0.3.0 -- the first stage's together,
// dual_stage last. Links address output slots by INDEX, so a node saved
// with the old order has its wires moved to the new slots once it is
// loaded (and the frontend has already renamed the saved slots after the
// new definition, so a save says which order it has by a property).

import { app } from "../../scripts/app.js";

const NODE = "H3SamplingSchedule";
const BUNDLE = "settings";
// sigmas, first_stage_sigmas, dual_stage, first_stage_width,
// first_stage_height (before 0.3.0) -> the new index of each
const OLD_TO_NEW = [0, 1, 4, 2, 3];
const ORDER_PROP = "obvpm_outputs";     // 2 = the 0.3.0 order
const ORDER = 2;

/** A node saved with the old output order: its wires onto the new slots.
 *  After the load, when every link's target is in the graph. */
function reorderOutputs(node) {
    const graph = node.graph;
    if (!graph || (node.outputs?.length ?? 0) !== OLD_TO_NEW.length) return;
    const wires = [];
    node.outputs.forEach((out, k) => {
        for (const id of out.links ?? []) {
            const link = linkOf(graph, id);
            if (link) wires.push({ to: k, target: link.target_id, slot: link.target_slot });
        }
    });
    if (!wires.length) return;
    for (let k = 0; k < node.outputs.length; k++) node.disconnectOutput?.(k);
    let moved = 0;
    for (const w of wires) {
        const target = graph.getNodeById?.(w.target);
        if (target && node.connect(OLD_TO_NEW[w.to], target, w.slot)) moved++;
    }
    if (moved !== wires.length) {
        console.warn(`[obvpm-h3] H3 Sampling Schedule #${node.id}: `
            + `${wires.length - moved} of ${wires.length} wires could not be `
            + "moved to the 0.3.0 output order");
    }
    graph.setDirtyCanvas?.(true, true);
}

function widget(node, name) {
    return (node.widgets ?? []).find((w) => w.name === name);
}

function linkOf(graph, id) {
    const links = graph?.links;
    if (!links || id == null) return null;
    // an object at the root, a Map inside a subgraph
    return typeof links.get === "function" ? links.get(id) : links[id];
}

/** Drop the widgets' sockets (only unlinked ones) and re-point the
 *  remaining links, which address slots by index. */
function dropSockets(node, names) {
    let changed = false;
    for (const name of names) {
        const at = (node.inputs ?? []).findIndex(
            (s) => s.widget && (s.widget.name === name || s.name === name));
        if (at < 0 || node.inputs[at].link != null) continue;
        node.removeInput(at);
        changed = true;
    }
    if (!changed) return;
    (node.inputs ?? []).forEach((slot, index) => {
        const link = linkOf(node.graph, slot.link);
        if (link) link.target_slot = index;
    });
}

function setShown(w, show) {
    if (!w) return;
    // both ways: the canvas renderer reads widget.hidden, the Vue one
    // widget.options.hidden
    w.hidden = !show;
    (w.options ??= {}).hidden = !show;
    const el = w.element ?? w.inputEl;
    if (el) el.style.display = show ? "" : "none";
}

function bundleWired(node) {
    const slot = (node.inputs ?? []).find((s) => s.name === BUNDLE);
    return slot?.link != null;
}

/** Hide what the bundle replaces while it is wired; true when anything
 *  changed. */
function apply(node, replaces) {
    const wired = bundleWired(node);
    let changed = false;
    for (const name of replaces) {
        const w = widget(node, name);
        if (!w) continue;
        if (!w.hidden !== !wired) changed = true;
        setShown(w, !wired);
    }
    return changed;
}

/** Fit the height to the rows now shown (the width stays the user's). */
function fitHeight(node) {
    const size = node.computeSize?.([node.size[0], node.size[1]]);
    if (!size) return;
    node.setSize([node.size[0], size[1]]);
    node.setDirtyCanvas?.(true, true);
}

app.registerExtension({
    name: "obvpm.h3_sampling_schedule",
    async beforeRegisterNodeDef(nodeType, nodeData) {
        if (nodeData?.name !== NODE) return;
        const replaces = nodeData.input?.optional?.[BUNDLE]?.[1]?.obvpm_replaces ?? [];
        if (!replaces.length) return;

        const onNodeCreated = nodeType.prototype.onNodeCreated;
        nodeType.prototype.onNodeCreated = function () {
            const r = onNodeCreated?.apply(this, arguments);
            (this.properties ??= {})[ORDER_PROP] = ORDER;
            // not now: a node being loaded (or pasted) is configured right
            // after it is made, and the frontend lines the saved inputs up
            // with the node's -- with sockets already gone, the saved links
            // landed on the wrong ones (width's on second_stage_x_steps).
            // A configured node drops them in onConfigure instead.
            queueMicrotask(() => {
                if (this.__obvpmSchedConfigured || !this.graph) return;
                dropSockets(this, replaces);
                if (apply(this, replaces)) fitHeight(this);
            });
            return r;
        };

        // configure() replays the saved links through onConnectionsChange,
        // which must not resize: the flag covers a node configured on its
        // own (paste), app.configuringGraph a whole load
        const configure = nodeType.prototype.configure;
        nodeType.prototype.configure = function () {
            this.__obvpmSchedConfiguring = true;
            try {
                return configure.apply(this, arguments);
            } finally {
                this.__obvpmSchedConfiguring = false;
            }
        };
        const onConfigure = nodeType.prototype.onConfigure;
        nodeType.prototype.onConfigure = function (info) {
            const r = onConfigure?.apply(this, arguments);
            // the SAVED properties: configure merges them over the ones
            // onNodeCreated set, so this.properties would always say new
            if (info?.properties?.[ORDER_PROP] !== ORDER) {
                setTimeout(() => reorderOutputs(this), 0);
            }
            (this.properties ??= {})[ORDER_PROP] = ORDER;
            this.__obvpmSchedConfigured = true;
            dropSockets(this, replaces);
            apply(this, replaces);
            return r;
        };

        const onConnectionsChange = nodeType.prototype.onConnectionsChange;
        nodeType.prototype.onConnectionsChange = function (type, index) {
            const r = onConnectionsChange?.apply(this, arguments);
            // 1 = an input
            if (type === 1 && this.inputs?.[index]?.name === BUNDLE) {
                const loading = app.configuringGraph || this.__obvpmSchedConfiguring;
                if (apply(this, replaces) && !loading) fitHeight(this);
            }
            return r;
        };
    },
});
