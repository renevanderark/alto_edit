var image_client = null;
var viewer = null;
var uncheckedChanges = false;
var resizing_windows = false;
var resize_x_position = 0;
var onInput = false;

// Array Remove - By John Resig (MIT Licensed)
Array.prototype.remove = function(from, to) {
  var rest = this.slice((to || from) + 1 || this.length);
  this.length = from < 0 ? this.length + from : from;
  return this.push.apply(this, rest);
};

document.onmousemove = function(e) {
	if(resizing_windows) {
		var curX = 0;
		if(e && e.clientX) { 
			curX = e.clientX;
		} else if(window.event.clientX) {
			curX = window.event.clientX;
		}
		resizeWindows(resize_x_position - curX);
		resize_x_position = curX;
	}
}

document.onmouseup = function(e) {
	if(resizing_windows) {
		new Ajax.Request(context_root + "/viewResize/" + book_urn, {
			"method": "post",
			"parameters": {
				"image_container_width": parseInt($('image_container').style.width),
				"ocr_container_width": parseInt($('ocr_container').style.width)
			}
		});
		resizing_windows = false;

		if(image_client)
			image_client.updateDims();
	}
}

document.onkeydown = function(e) {
	var code, shift, ctrl = null;
	if(!e) code = window.event.keyCode; else code = e.keyCode || e.which;
	if(!e) ctrl = window.event.ctrlKey; else ctrl = e.ctrlKey;
	if(!e) shift = window.event.shiftKey; else shift = e.shiftKey;

	if(code == 83 && ctrl == 1) { 
		viewer.saveCurrentUpdate(); 
		if(shift == 1) {
			if(confirm("Weet u zeker dat u deze pagina definitief wilt opslaan en verdergaan? Wijzigingen zijn hierna niet meer mogelijk"))
				$('update_form').insert(new Element("input", {"name": "finalize", "value": "true", "type": "hidden"}));
			else
				return false;
		}
/*		$('image_container').hide(); 
		$('ocr_container').hide(); 
		$('spinner_div').show();*/

		$('update_form').submit();
		return false;
	}
	if(code == 8 && $$(".altoLineDiv input").length == 0 && !onInput) {
		return false;
	}
}

function altoFrom(version) {
	json_alto("reinitAltoText", version);
}


function confirmChanges() {
	viewer.saveCurrentUpdate();
	var i = $$('#update_form input').length - 1;
	if(i > 0) {
		if(confirm("De laatste wijzigingen zijn niet opgeslagen, wilt u eerste de wijzigingen opslaan?")) {
			$('image_container').hide(); $('ocr_container').hide(); $('spinner_div').show();
			$('update_form').submit();
		} else {
			$('image_container').hide(); $('ocr_container').hide(); $('spinner_div').show();
			return true;
		}
	} else {
		$('image_container').hide(); $('ocr_container').hide(); $('spinner_div').show();
		return true;
	}
}

function leadingZero(x) {
	var y = "" + x;
	var retStr = "";
	for(var i = 0; i < 4 - y.length; ++i)
		retStr += "0";
	return retStr + y;
}

function viewport() {
	if(document.body.clientWidth && document.body.clientHeight)
		return {width: document.body.clientWidth, height: document.body.clientHeight};
	else
		return {width: 950, height: 600};
}

function scaleWindows(img_width, ocr_width) {
	var dims = viewport();
	if(img_width && ocr_width) {
		$('image_container').style.width = img_width + "px";
		if(ocr_width + 20 + img_width > dims.width)
			ocr_width -= (ocr_width + 20 + img_width - dims.width)
		$('ocr_container').style.width = ocr_width + "px";
		$('ocr_container').style.height = (dims.height - 170) + "px";
		$('image_container').style.height = (dims.height - 170) + "px";
	} else {
		[['image_container', 1.9], ['ocr_container', 2.5]].each(function(x) {
			$(x[0]).style.width = (dims.width / x[1]) + "px";
			$(x[0]).style.height = (dims.height - 170) + "px";
			if(image_client && x[0] == 'image_container') 
				image_client.updateDims();					
		});
	}
}

function resizeWindows(movement) {
	$('image_container').style.width = (parseInt($('image_container').style.width) - movement) + "px";
	$('ocr_container').style.width = (parseInt($('ocr_container').style.width) + movement) + "px";
}


function addNavigationObservers() {
	$$('.navigation_link').each(function(elem) { 
		elem.observe("click", function(e) {
			if($$('#update_form input').length - 3 > 0)
				uncheckedChanges = true;
		})
	});
}

function validateUnload() {
	if(uncheckedChanges)  {
		uncheckedChanges = false;
		return "Sommige wijzigingen zijn niet opgeslagen";
	}

	if(!validateSegmentation()) {
		uncheckedChanges = false;
		return "In 1 of meerdere regels komt het aantal woorden niet overeen met het aantal segmenten";
	}
}

function preventDefault(e) {
	if (e.preventDefault) e.preventDefault();
	return false;
}

function validateSegmentation() {
	var retVal = true;
	$$(".altoLineDiv").each(function(div) {
		if(!viewer.validateSegments(div))
			retVal = false;
	});
	return retVal;
}

function drag_resize_start(e) {
	resizing_windows = true;
	if(e.clientX)
		resize_x_position = e.clientX;
	else if(window.event && window.event.pageX)
		resize_x_position = window.event.pageX;
}
