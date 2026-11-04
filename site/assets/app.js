// Renders the last recorded run. No framework, no build step, no client-side state.
(function () {
  'use strict';

  var STATUS_TEXT = {
    pass: 'pass',
    fail: 'fail',
    caught: 'caught',
    'not-caught': 'not caught',
    error: 'error'
  };

  function el(tag, className, text) {
    var node = document.createElement(tag);
    if (className) node.className = className;
    if (text != null) node.textContent = String(text);
    return node;
  }

  function chip(id, text) {
    var node = document.getElementById(id);
    if (node) node.textContent = text;
  }

  function renderMeta(report, manifest) {
    var commit = (manifest && manifest.commit) || report.commit || 'local';
    chip('chip-commit', 'commit ' + String(commit).slice(0, 7));
    chip('chip-postgres', 'postgres ' + (report.postgres || '—'));
    chip('chip-generated', 'generated ' + (report.generatedAt || '—'));

    if (manifest && manifest.runUrl) {
      var p = el('p', 'small');
      var a = el('a', null, 'This recorded run on GitHub Actions');
      a.href = manifest.runUrl;
      p.appendChild(a);
      document.getElementById('run-link').appendChild(p);
    }
  }

  function renderScenario(scenario) {
    var card = el('article', 'card');

    var title = el('h3');
    title.appendChild(el('span', 'num', scenario.id));
    title.appendChild(el('span', null, scenario.title));
    card.appendChild(title);

    var status = el('span', 'status ' + scenario.status, STATUS_TEXT[scenario.status] || scenario.status);
    status.title = scenario.expectedFail
      ? 'This scenario is bad on purpose; it passes only when the harness catches it.'
      : 'Passes when assertions hold and the writer stays inside its latency budget.';
    card.appendChild(status);

    var steps = el('ul', 'steps');
    (scenario.steps || []).forEach(function (step) {
      var li = el('li');
      li.appendChild(el('span', null, step.name));
      li.appendChild(el('span', 'ms', step.ms + ' ms'));
      steps.appendChild(li);
    });
    card.appendChild(steps);

    var budget = scenario.lockBudgetMs || 0;
    var worst = scenario.maxLockMs || 0;
    var lock = el('div', 'lock');
    var bar = el('div', 'bar');
    var fill = el('div', 'fill' + (worst > budget ? ' over' : ''));
    fill.style.width = Math.min(100, budget > 0 ? (worst / budget) * 100 : 0) + '%';
    bar.appendChild(fill);
    lock.appendChild(bar);
    lock.appendChild(el('div', 'label',
      'worst writer wait ' + worst + ' ms · budget ' + budget + ' ms'));
    card.appendChild(lock);

    if (scenario.notes && scenario.notes !== 'none') {
      card.appendChild(el('p', 'notes', scenario.notes));
    }

    return card;
  }

  function render(report, manifest) {
    renderMeta(report, manifest);

    var host = document.getElementById('scenarios');
    var hint = document.getElementById('results-hint');
    var scenarios = report.scenarios || [];

    host.textContent = '';

    if (!scenarios.length) {
      hint.textContent = report.error
        ? 'The last run produced no results: ' + report.error
        : 'The last run produced no results yet.';
      hint.className = 'hint error';
      return;
    }

    scenarios.forEach(function (scenario) { host.appendChild(renderScenario(scenario)); });

    var failed = scenarios.filter(function (s) {
      return s.status === 'fail' || s.status === 'not-caught' || s.status === 'error';
    }).length;

    hint.textContent = scenarios.length + ' scenarios · ' +
      (failed ? failed + ' failing' : 'all within their budgets');
    hint.className = 'hint' + (failed ? ' error' : '');
  }

  fetch('data/report.json', { cache: 'no-store' })
    .then(function (response) {
      if (!response.ok) throw new Error('HTTP ' + response.status);
      return response.json();
    })
    .then(function (report) { render(report, window.LAB || {}); })
    .catch(function (error) {
      var hint = document.getElementById('results-hint');
      hint.textContent = 'Could not load the recorded report (' + error.message + ').';
      hint.className = 'hint error';
    });
})();
