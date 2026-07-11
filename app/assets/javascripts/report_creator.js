// CIF.ReportCreator — Chart.js v4 (MIT) implementation.
//
// UNIT 11: replaced the former proprietary v5.0.6 (2016) charting library with Chart.js
// v4.4.7 (MIT, vendored UMD at vendor/assets/javascripts/chart.umd.js, required as
// `chart.umd` in application.js). Core Chart.js ONLY — NO plugins (no datalabels, no date
// adapter). The three chart types the app uses map onto core controllers:
//   lineChart  — categorical multi-series spline (CSI-domain scores; case statistics)
//   pieChart   — single pie with click-through slices (client-by-status; family-type)
//   donutChart — two concentric doughnut rings (outer Case, inner Gender), click-through
//                on the outer (Case) ring
//
// Rendering approach (canvas INJECTION): every container in the views is a <div> carrying
// data-* attributes the callers read BEFORE building the chart. Rather than churn each view
// to a %canvas (and disturb the data-* hosting / box sizing), we KEEP the div and inject a
// fresh <canvas> child at init time, then build the Chart on that canvas. Lowest-churn and
// fully re-init-safe.
//
// Re-init safety: Chart.js throws "Canvas is already in use" if a chart is constructed on a
// canvas that still owns a live instance. _canvasFor() destroys any prior chart bound to the
// container, empties the div, and creates a BRAND-NEW canvas, so a re-run (window 'resize'
// dispatch, slideToggle, .minimalize-styl-2 handler, or a controller _init re-entry) can never
// raise that error.
//
// Height: the former library supplied chart height in JS (pie/donut height 380; line ~400px
// default). Chart.js with maintainAspectRatio:false sizes the canvas to the PARENT block's
// height, and the containers have NO CSS height — a bare div would collapse the canvas to ~0px.
// _canvasFor() therefore sets an explicit pixel height on the container per chart type so the
// canvas fills a real box (parity with the old heights).
//
// @element is a jQuery object (callers pass `$('#...')`). _container() resolves the raw DOM node.

const Cls = (CIF.ReportCreator = class ReportCreator {
  static initClass() {
    // Shared palette — MUST match the former `colors:` array exactly.
    //   green #59b260, blue #5096c9, africa #1c8781, brown #B2912F, yellow #DECF3F
    this.PALETTE = ['#59b260', '#5096c9', '#1c8781', '#B2912F', '#DECF3F'];

    // Container heights restoring the former render sizes.
    this.LINE_HEIGHT = 400;
    this.PIE_HEIGHT = 380;
  }

  constructor(data, title, yAxisTitle, element) {
    this.data = data;
    this.title = title;
    this.yAxisTitle = yAxisTitle;
    this.element = element;
  }

  perform() {
    this.lineChart();
    this.pieChart();
    return this.donutChart();
  }

  // ---- container / canvas management (re-init safe) ---------------------------------------
  // Resolve the raw container DOM node from the jQuery-or-DOM @element the callers hand us.
  _container() {
    const el = this.element;
    if (el && el.jquery) {
      return el[0];
    } else {
      return el;
    }
  }

  // Return a pristine <canvas> to draw on. Destroys any Chart previously built on this
  // container (guards "Canvas is already in use"), sets a real height (so maintainAspectRatio:
  // false has a box to fill), clears the div, and appends a new canvas.
  _canvasFor(container, heightPx) {
    if (!container) {
      return null;
    }
    if (container._cifChart) {
      try {
        container._cifChart.destroy();
      } catch (e) {}
      // already destroyed / detached — nothing to do
      container._cifChart = null;
    }
    if (heightPx) {
      container.style.height = `${heightPx}px`;
    }
    container.innerHTML = '';
    const canvas = document.createElement('canvas');
    container.appendChild(canvas);
    return canvas;
  }

  // Build the Chart and remember it on the container for later teardown.
  _render(container, canvas, config) {
    const chart = new Chart(canvas, config);
    container._cifChart = chart;
    return chart;
  }

  // ---- line chart (categorical x-axis "spline") -------------------------------------------
  // data = [ labels, series ]
  //   labels = ["Assessment (1)", ...] (CSI) | ["Jan 2026", ...] (case) — pre-formatted strings.
  //   series = [ { name: "...", data: [num, num, null, ...] }, ... ]  (values may be null => gaps)
  // Former type:'spline' + connectNulls:true  =>  Chart.js line with tension 0.4 + spanGaps.
  // yAxis.allowDecimals:false  =>  integer-ish y ticks (precision 0).
  lineChart() {
    if (this.data === undefined) {
      return;
    }
    const container = this._container();
    const canvas = this._canvasFor(container, CIF.ReportCreator.LINE_HEIGHT);
    if (!canvas) {
      return;
    }

    const palette = CIF.ReportCreator.PALETTE;
    const datasets = (this.data[1] || []).map(function (s, i) {
      const color = palette[i % palette.length];
      return {
        label: s.name,
        data: s.data,
        spanGaps: true, // connectNulls: draw across null points
        tension: 0.4, // spline-equivalent smoothing
        fill: false,
        borderColor: color,
        backgroundColor: color,
        pointBackgroundColor: color,
      };
    });

    const config = {
      type: 'line',
      data: {
        labels: this.data[0],
        datasets,
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        interaction: {
          mode: 'index', // shared-tooltip equivalent
          intersect: false,
        },
        plugins: {
          legend: {
            position: 'top',
          },
          title: {
            display: !!this.title,
            text: this.title,
          },
          tooltip: {
            mode: 'index',
            intersect: false,
          },
        },
        scales: {
          x: {
            type: 'category',
          }, // CATEGORICAL — pre-formatted string labels, NOT a time scale
          y: {
            beginAtZero: true,
            title: {
              display: !!this.yAxisTitle,
              text: this.yAxisTitle,
            },
            ticks: {
              precision: 0,
            },
          },
        },
      }, // allowDecimals: false
    };

    return this._render(container, canvas, config);
  }

  // ---- donut chart (two concentric rings) -------------------------------------------------
  // data = [ {name:"Males",   y:N, active_data:[{name,y,url}, ...]},
  //          {name:"Females", y:N, active_data:[{name,y,url}, ...]} ]
  // inner ring (Gender): labels [data[0].name, data[1].name], values [data[0].y, data[1].y]
  // outer ring (Case):   data[0].active_data.concat(data[1].active_data) — each {name,y,url};
  //                      clicking an outer slice navigates to that entry's url.
  //
  // Chart.js doughnut STACKS multiple datasets into concentric rings by per-dataset `weight`
  // (do NOT set per-dataset `radius` — that collapses both bands onto the same cutout and they
  // OVERLAP). Dataset index 0 is the OUTERMOST ring (outerRadius = R - v*ringWeightOffset(0) = R),
  // higher indices stack inward. So dataset 0 = Case (outer, clickable), dataset 1 = Gender
  // (inner) — matching the former layout (Gender inner size 60%, Case outer ring 60%->100%).
  donutChart() {
    if (this.data === undefined) {
      return;
    }
    const container = this._container();
    const canvas = this._canvasFor(container, CIF.ReportCreator.PIE_HEIGHT);
    if (!canvas) {
      return;
    }

    const palette = CIF.ReportCreator.PALETTE;
    const inner = this.data.slice(0, 2);
    const outer = ((inner[0] != null ? inner[0].active_data : undefined) || []).concat(
      (inner[1] != null ? inner[1].active_data : undefined) || [],
    );

    const innerLabels = inner.map((g) => g.name);
    const innerValues = inner.map((g) => g.y);
    const outerLabels = outer.map((c) => c.name);
    const outerValues = outer.map((c) => c.y);
    const outerUrls = outer.map((c) => c.url);

    const colorsFor = (n) => __range__(0, n, false).map((i) => palette[i % palette.length]);

    const config = {
      type: 'doughnut',
      data: {
        // Chart.js builds the legend from data.labels (a single label set). Use the OUTER
        // (Case) labels — the informative, clickable ring — matching the former Case series'
        // showInLegend:true. Inner Gender values surface via tooltip.
        labels: outerLabels,
        datasets: [
          {
            // dataset 0 => OUTER ring (Case, clickable)
            label: 'Case',
            data: outerValues,
            _labels: outerLabels,
            _urls: outerUrls,
            backgroundColor: colorsFor(outerValues.length),
            weight: 1, // thinner outer ring (former Case band 60%->100%)
          },
          {
            // dataset 1 => INNER ring (Gender)
            label: 'Gender',
            data: innerValues,
            _labels: innerLabels,
            backgroundColor: colorsFor(innerValues.length),
            weight: 1.5, // fatter inner ring (former Gender disk 0->60%)
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        cutout: '25%',
        plugins: {
          legend: {
            position: 'top',
            labels: {
              font: {
                size: 11,
              },
            },
          },
          title: {
            display: false,
          },
          tooltip: {
            callbacks: {
              // "<slice name>: <value>" — parity with the former in-slice dataLabels formatter,
              // pulling the per-slice name from the dataset's _labels array.
              label(ctx) {
                const ds = ctx.dataset;
                const name = (ds._labels && ds._labels[ctx.dataIndex]) || ctx.label || '';
                return `${name}: ${ctx.parsed}`;
              },
            },
          },
        },
        onClick(event, elements, chart) {
          if (!elements || !elements.length) {
            return;
          }
          const el = elements[0];
          const ds = chart.data.datasets[el.datasetIndex];
          const url = ds._urls && ds._urls[el.index];
          if (url) {
            return (location.href = url);
          }
        },
        onHover(event, elements) {
          const target = event.native != null ? event.native.target : undefined;
          if (!target) {
            return;
          }
          return (target.style.cursor = elements && elements.length ? 'pointer' : 'default');
        },
      },
    };

    return this._render(container, canvas, config);
  }

  // ---- pie chart (single ring, clickable slices) ------------------------------------------
  // data = [ {name, y, url}, {name, y, url}, ... ]
  //   NOTE: some names come from *_html i18n keys and MAY contain HTML markup. Chart.js draws
  //   legend/label text as CANVAS TEXT (not innerHTML), so any tags render literally — no XSS,
  //   parity-acceptable. Click a slice -> navigate to data[i].url.
  pieChart() {
    if (this.data === undefined) {
      return;
    }
    const container = this._container();
    const canvas = this._canvasFor(container, CIF.ReportCreator.PIE_HEIGHT);
    if (!canvas) {
      return;
    }

    const palette = CIF.ReportCreator.PALETTE;
    const entries = this.data || [];
    const labels = entries.map((d) => d.name);
    const values = entries.map((d) => d.y);
    const urls = entries.map((d) => d.url);
    const colors = __range__(0, entries.length, false).map((i) => palette[i % palette.length]);

    const config = {
      type: 'pie',
      data: {
        labels,
        datasets: [
          {
            data: values,
            backgroundColor: colors,
            _urls: urls,
          },
        ],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'top',
            labels: {
              font: {
                size: 15,
              },
            },
          },
          title: {
            display: false,
          },
          tooltip: {
            callbacks: {
              // "<name>: <value>" — parity with the former tooltip/dataLabels formatter.
              label(ctx) {
                return `${ctx.label}: ${ctx.parsed}`;
              },
            },
          },
        },
        onClick(event, elements, chart) {
          if (!elements || !elements.length) {
            return;
          }
          const el = elements[0];
          const ds = chart.data.datasets[el.datasetIndex];
          const url = ds._urls && ds._urls[el.index];
          if (url) {
            return (location.href = url);
          }
        },
        onHover(event, elements) {
          const target = event.native != null ? event.native.target : undefined;
          if (!target) {
            return;
          }
          return (target.style.cursor = elements && elements.length ? 'pointer' : 'default');
        },
      },
    };

    return this._render(container, canvas, config);
  }
});
Cls.initClass();

function __range__(left, right, inclusive) {
  let range = [];
  let ascending = left < right;
  let end = !inclusive ? right : ascending ? right + 1 : right - 1;
  for (let i = left; ascending ? i < end : i > end; ascending ? i++ : i--) {
    range.push(i);
  }
  return range;
}
