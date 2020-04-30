function commitUpdate(c,t) {
  if (c.checked) {
    t.className = 'commit-checked-true';
  } else {
    t.className = 'commit-checked-false';
  }
}

function clickOnCommit(e) {
  var t = e.currentTarget;

  if (!t.id.startsWith('commit-tr-')) {
    console.log('Click event on row eaten by Cthulhu.');
  }

  var sha = t.id.slice(10);
  var checkbox = document.getElementById('commit-check-' + sha);

  checkbox.checked = ! checkbox.checked;
  commitUpdate(checkbox, t);
}

function commitsLoad() {
  var elts = document.getElementById('commits-form').elements;
  var l = elts.length;
  for (var i=1; i<l; i++) {
    elts.item(i).parentNode.style.display = "none";
    elts.item(i).parentNode.parentNode.addEventListener("click", function (e) { clickOnCommit(e); });
    commitUpdate(elts.item(i), elts.item(i).parentNode.parentNode);
  }

  document.getElementById('filter-selected').addEventListener("change", filterReload);
  document.getElementById('filter-refs').addEventListener("change", filterReload);

  document.getElementById('filter-string').addEventListener("input", filterStringReload);
}

function classNames(elt) {
  return elt.className.split(" ");
}

function hasClass(elt, name) {
  var cns = classNames(elt);
  for (var i=0; i<cns.length; i++) {
    if (cns[i] == name)
      return true;
  }

  return false;
}

function classAdd(elt, name) {
  var cns = classNames(elt);
  for (var i=0; i<cns.length; i++) {
    if (cns[i] == name)
      return;
  }

  cns.push(name);
  elt.className = cns.join(" ");
}

function classDel(elt, name) {
  var cns = classNames(elt).filter(function (x) { return x != name; });
  elt.className = cns.join(" ");
}

var searchString = "";

function filterStringReload() {
  var fsv = document.getElementById('filter-string').value;
  if (fsv.length < 4) {
    if (searchString == "")
      return;

    searchString = "";
  } else {
    if (searchString == fsv)
      return;

    searchString = fsv;
  }

  filterReload();
}

function filterReload() {
  var selected = document.getElementById('filter-selected').checked;
  var refs = document.getElementById('filter-refs').checked;

  var elts = document.getElementById('commits-form').elements;
  var l = elts.length;
  for (var i=1; i<l; i++) {
    var show = true;
    var box = elts.item(i);

    if (selected && !box.checked) {
      show = false;
    }

    var hasref = true;
    var tr = box.parentNode.parentNode;
    if (searchString.length > 0 && !(tr.id.startsWith("commit-tr-" + searchString) || tr.textContent.includes(searchString))) {
      show = false;
    }

    for (var cn=0; cn<tr.childNodes.length; cn++) {
      var td = tr.childNodes[cn];
      if (td.nodeName == "TD" && hasClass(td, 'commit')) {
	for (var cd=0; cd<td.childNodes.length; cd++) {
	  var div = td.childNodes[cd];
	  if (div.nodeName == "DIV" && hasClass(div, 'refs')) {
	    hasref = div.childNodes.length != 0;
	  }
	}
	break;
      }
    }

    if (refs && !hasref) {
      show = false;
    }

    if (!show) {
      classAdd(tr, "filter-hide");
    } else {
      classDel(tr, "filter-hide");
    }
  }
}

function doRollOut(e) {
  var ctl = e.target;
  var tgt = document.getElementById("rollout-" + ctl.id.split("-")[1] + "-tgt");

  if (hasClass(tgt, 'rollout-tgt-show')) {
    ctl.innerHTML = "+";
    classDel(tgt, "rollout-tgt-show");
  } else {
    ctl.innerHTML = "-";
    classAdd(tgt, "rollout-tgt-show");
  }
}
