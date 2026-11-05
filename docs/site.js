// Every number on the site comes from benchmarks.json, which `rake bench` rewrites before each release.
const METRICS = [
  { key: "renders_per_second", title: "Renders per second", better: "higher" },
  { key: "compiles_per_second", title: "Compiles per second", better: "higher" },
  { key: "render_allocations", title: "Objects allocated per render", better: "lower" },
  { key: "compile_allocations", title: "Objects allocated per compile", better: "lower" }
];

const element = (tag, attributes = {}, ...children) => {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(attributes)) {
    if (name === "style") Object.entries(value).forEach(([property, setting]) => node.style.setProperty(property, setting));
    else node.setAttribute(name, value);
  }
  node.append(...children);
  return node;
};
const formatNumber = (value) => value.toLocaleString("en");
const formatRatio = (ratio) => `${Number(ratio.toFixed(ratio < 10 ? 1 : 0))}×`;
const formatSeconds = (milliseconds) => milliseconds < 1000 ? `${formatNumber(milliseconds)} ms` : `${(milliseconds / 1000).toFixed(1)} s`;
const named = (list, name) => list.find((entry) => entry.name === name);
const fill = (selector, text) => document.querySelectorAll(selector).forEach((node) => { node.textContent = text; });

function columnChart({ title, better, rows, format = formatNumber }) {
  const maximum = Math.max(...rows.map((row) => row.value));
  const columns = element("div", { class: "columns", style: { "--count": rows.length }, role: "img", "aria-label": `${title}: ${rows.map((row) => `${row.name} ${format(row.value)}`).join(", ")}` });
  for (const row of rows) {
    const superSlim = row.name.startsWith("SuperSlim") || row.name.startsWith("super_slim") ? " super_slim" : "";
    columns.append(element("div", { class: `column${superSlim}`, title: `${row.label || row.name}: ${format(row.value)}` },
      element("span", { class: "column-value" }, format(row.value)),
      element("div", { class: `column-bar${superSlim}`, style: { height: `${(row.value / maximum) * 100}%` } }),
      element("span", { class: "column-name" }, row.name)));
  }
  const table = element("table", {},
    element("thead", {}, element("tr", {}, element("th", { scope: "col" }, "Engine"), element("th", { scope: "col", class: "number" }, title))),
    element("tbody", {}, ...rows.map((row) => element("tr", {},
      element("td", {}, row.label || row.name),
      element("td", { class: "number" }, format(row.value))))));
  return element("figure", { class: "chart" },
    element("h3", {}, `${title} `, element("small", {}, `(${better} is better)`)),
    columns,
    element("details", {}, element("summary", {}, "Table"), table));
}

function speedups(benchmarks) {
  const compile = benchmarks.corpora.map((corpus) => named(corpus.engines, "Slim").milliseconds / named(corpus.engines, "SuperSlim").milliseconds);
  const superSlim = named(benchmarks.engines, "SuperSlim");
  const slim = named(benchmarks.engines, "Slim");
  const slimLint = benchmarks.tools?.commands.find((command) => command.name.startsWith("slim-lint"));
  return {
    // The smaller of the corpora ratios: the headline never picks the flattering one.
    compile: compile.length ? Math.min(...compile) : superSlim.compiles_per_second / slim.compiles_per_second,
    render: superSlim.renders_per_second / slim.renders_per_second,
    renderAllocations: slim.render_allocations / superSlim.render_allocations,
    // CPU time, not wall time: super_slim spreads over every core, slim-lint uses one, so wall time depends on the machine.
    lint: slimLint && slimLint.cpu_milliseconds / named(benchmarks.tools.commands, "super-slim lint").cpu_milliseconds
  };
}

function measuredOn(benchmarks) {
  const ruby = benchmarks.ruby.split(" (")[0].replace("ruby", "Ruby");
  return `Measured ${benchmarks.measured_on} on ${ruby}${benchmarks.yjit ? " with YJIT" : ""}.`;
}

function renderHome(benchmarks) {
  const ratio = speedups(benchmarks);
  fill("#byline-speed", `Slim templates, compiled ${formatRatio(ratio.compile)} faster.`);
  fill("[data-sha='Slim']", benchmarks.html_sha256.Slim);
  fill("[data-sha='SuperSlim']", benchmarks.html_sha256["SuperSlim"]);
  fill("[data-version='Slim']", `Slim ${named(benchmarks.engines, "Slim").version}`);

  const tiles = document.getElementById("tiles");
  if (!tiles) return;
  const largest = benchmarks.corpora.reduce((largest, corpus) => corpus.templates > largest.templates ? corpus : largest);
  const tile = (value, label, detail) => element("div", { class: "tile" },
    element("span", { class: "tile-value" }, value), element("span", { class: "tile-label" }, label), element("span", { class: "tile-detail" }, detail));
  tiles.append(
    tile(formatRatio(ratio.compile), "faster compilation", `${formatNumber(largest.templates)} real templates: ${formatSeconds(named(largest.engines, "SuperSlim").milliseconds)} instead of ${formatSeconds(named(largest.engines, "Slim").milliseconds)}`),
    tile(formatRatio(ratio.render), "faster rendering", `${formatNumber(named(benchmarks.engines, "SuperSlim").renders_per_second)} pages a second; plain ERB with Erubi: ${formatNumber(named(benchmarks.engines, "Erubi").renders_per_second)}`),
    tile(formatRatio(ratio.renderAllocations), "fewer allocations per render", `${named(benchmarks.engines, "SuperSlim").render_allocations} objects instead of ${named(benchmarks.engines, "Slim").render_allocations}`));
  if (ratio.lint) {
    const slimLint = benchmarks.tools.commands.find((command) => command.name.startsWith("slim-lint"));
    tiles.append(tile(formatRatio(ratio.lint), "less CPU than slim-lint",
      `${formatNumber(benchmarks.tools.templates)} templates: ${formatSeconds(named(benchmarks.tools.commands, "super-slim lint").milliseconds)} on ${benchmarks.tools.processors} cores, ${formatSeconds(slimLint.milliseconds)} for slim-lint on one`));
  }
  fill("#tiles-note", `${measuredOn(benchmarks)} Compilation is the slower of the two corpora on the benchmarks page.`);
}

function renderBenchmarks(benchmarks) {
  fill("#bench-note", `The same page — ${benchmarks.page} — written in Slim, Haml and ERB, compiled and rendered by each engine, which all produce the same HTML. ${measuredOn(benchmarks)}`);
  const charts = document.getElementById("charts");
  for (const metric of METRICS) {
    charts.append(columnChart({ ...metric, rows: benchmarks.engines.map((engine) => ({ name: engine.name, label: `${engine.name} ${engine.version}`, value: engine[metric.key] })) }));
  }

  const versionByName = Object.fromEntries(benchmarks.engines.map((engine) => [engine.name, engine.version]));
  const corpora = document.getElementById("corpora");
  for (const corpus of benchmarks.corpora) {
    const rowsFor = (key) => corpus.engines.map((engine) => ({ name: engine.name, label: `${engine.name} ${versionByName[engine.name]}`, value: engine[key] }));
    corpora.append(element("div", { class: "corpus" },
      element("h3", {}, `${corpus.label}: ${formatNumber(corpus.templates)} templates`),
      element("div", { class: "charts" },
        columnChart({ title: "Time to compile them all", better: "lower", rows: rowsFor("milliseconds"), format: formatSeconds }),
        columnChart({ title: "Objects allocated", better: "lower", rows: rowsFor("allocations") }))));
  }

  const tools = benchmarks.tools;
  if (!tools) return;
  const rowsFor = (key) => tools.commands.map((command) => ({ name: command.name.replace(/ \d[\d.]*$/, ""), label: command.name, value: command[key] }));
  document.getElementById("tools").append(
    element("h3", {}, `${formatNumber(tools.templates)} templates of the open-source corpus`),
    element("div", { class: "charts" },
      columnChart({ title: "Wall time", better: "lower", rows: rowsFor("milliseconds"), format: formatSeconds }),
      columnChart({ title: "CPU time, all processes", better: "lower", rows: rowsFor("cpu_milliseconds"), format: formatSeconds })));
  fill("#tools-note", `super-slim splits the templates between ${tools.processors} processes, one per core; slim-lint uses one. CPU time adds up every process, so it compares the work itself. slim-lint runs without its RuboCop linter, which SuperSlim has no equivalent of. Median of 3 runs.`);
}

fetch("benchmarks.json").then((response) => response.json()).then((benchmarks) => {
  renderHome(benchmarks);
  if (document.getElementById("charts")) renderBenchmarks(benchmarks);
}).catch(() => {
  fill("#bench-note, #tiles-note", "The benchmark numbers could not be loaded: see docs/benchmarks.json in the repository.");
});
