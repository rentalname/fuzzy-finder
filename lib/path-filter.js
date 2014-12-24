module.exports = filter;

var path = require("path");

function filter(pattern, list, options) {
  options = options || {};
  var key = options.key,
    pre = options.pre || "",
    post = options.post || "",
    results = [];

  pattern = pattern.replace(/\/$/, "");

  for (var i = 0; i < list.length; i++) {
    var original = list[i];
    var name = key ? original[key] : original;
    var res = match(pattern, name, pre, post);
    if (res.score) {
      results.push({original: original, result: res});
    }
  }

  return results.sort(function(a,b) {
    return b.result.score - a.result.score;
  });
}

function match(pattern, name, pre, post) {
  var patterns = pattern.split(path.sep).reverse(),
    names = name.split(path.sep).reverse(),
    nameIndex = 0,
    score = 0,
    i = 0;

  for (; i < patterns.length; i++) {
    var p = patterns[i];

    if (!p.length) nameIndex++;
    if (nameIndex > names.length) return 0; // no match.

    var match = false;
    for (;nameIndex < names.length; nameIndex++) {
      var n = names[nameIndex];

      if (n.toUpperCase() == p.toUpperCase()) {
        names[nameIndex] = pre + n + post;
        score += p.length * 10;
        break;
      }

      var res = fuzzyMatch(p, n, pre, post);
      names[nameIndex] = res.match;
      score += res.score;
      if (res.score) {
        match = true;
        break;
      }
    }
    if (!match) {
      return {
        match: name,
        score: 0
      };
    }
  }
  return {
    match: names.reverse().join(path.sep),
    score: score
  };
}

function fuzzyMatch(pattern, val, pre, post) {
  var score = 0,
    valIndex = 0,
    last = -1,
    bonus = 0,
    dotPos = val.indexOf(".");
  if (dotPos != -1) dotPos--;

  var caps = val.replace(/[^A-Z]/g, "");
  if (caps == pattern.toUpperCase()) {
    return {
      match: val.replace(/([A-Z])/g, function(v) { return pre + v + post; }),
      score: val.length * 10
    };
  }

  var matches = [];
  for (var i = 0; i < val.length; i++) matches.push(val[i]);
  for (var i = 0; i < pattern.length; i++) {
    var p = pattern[i];
    var match = false;
    for (; valIndex < val.length; valIndex++) {
      var v = val[valIndex];
      if (p.toUpperCase() == v.toUpperCase()) {
        score++;
        matches[valIndex] = pre + v + post;
        if (v.match(/[A-Z]/)) score += 4;
        if (valIndex == 0) bonus += 10;
        if (last == valIndex-1) {
          bonus += 4;
          score += bonus;
        } else {
          bonus = 0;
        }
        last = valIndex;
        match = true;
        valIndex++;
        break;
      }
    }
    if (!match) {
      return {
        match: val,
        score: 0
      };
    }
  }
  return {
    match: matches.join(""),
    score: score
  };
}
