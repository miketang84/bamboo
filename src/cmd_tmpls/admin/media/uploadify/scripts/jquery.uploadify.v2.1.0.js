/*
Uploadify v2.1.0
Release Date: August 24, 2009

Copyright (c) 2009 Ronnie Garcia, Travis Nickels

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

if(jQuery)(
	function($){
		jQuery.extend(jQuery.fn,{
			uploadify:function(options) {
				$(this).each(function(){
					settings = $.extend({
					id             : $(this).attr('id'), // The ID of the object being Uploadified
					uploader       : 'uploadify.swf', // The path to the uploadify swf file
					script         : 'uploadify.php', // The path to the uploadify backend upload script
					expressInstall : null, // The path to the express install swf file
					folder         : '', // The path to the upload folder
					height         : 30, // The height of the flash button
					width          : 110, // The width of the flash button
					cancelImg      : 'cancel.png', // The path to the cancel image for the default file queue item container
					wmode          : 'opaque', // The wmode of the flash file
					scriptAccess   : 'sameDomain', // Set to "always" to allow script access across domains
					fileDataName   : 'Filedata', // The name of the file collection object in the backend upload script
					method         : 'POST', // The method for sending variables to the backend upload script
					queueSizeLimit : 999, // The maximum size of the file queue
					simUploadLimit : 1, // The number of simultaneous uploads allowed
					queueID        : false, // The optional ID of the queue container
					displayData    : 'percentage', // Set to "speed" to show the upload speed in the default queue item
					onInit         : function() {}, // Function to run when uploadify is initialized
					onSelect       : function() {}, // Function to run when a file is selected
					onQueueFull    : function() {}, // Function to run when the queue reaches capacity
					onCheck        : function() {}, // Function to run when script checks for duplicate files on the server
					onCancel       : function() {}, // Function to run when an item is cleared from the queue
					onError        : function() {}, // Function to run when an upload item returns an error
					onProgress     : function() {}, // Function to run each time the upload progress is updated
					onComplete     : function() {}, // Function to run when an upload is completed
					onAllComplete  : function() {}  // Functino to run when all uploads are completed
				}, options);
				var pagePath = location.pathname;
				pagePath = pagePath.split('/');
				pagePath.pop();
				pagePath = pagePath.join('/') + '/';
				var data = {};
				data.uploadifyID = settings.id;
				data.pagepath = pagePath;
				if (settings.buttonImg) data.buttonImg = escape(settings.buttonImg);
				if (settings.buttonText) data.buttonText = escape(settings.buttonText);
				if (settings.rollover) data.rollover = true;
				data.script = settings.script;
				data.folder = escape(settings.folder);
				if (settings.scriptData) {
					var scriptDataString = '';
					for (var name in settings.scriptData) {
						scriptDataString += '&' + name + '=' + settings.scriptData[name];
					}
					data.scriptData = escape(scriptDataString.substr(1));
				}
				data.width          = settings.width;
				data.height         = settings.height;
				data.wmode          = settings.wmode;
				data.method         = settings.method;
				data.queueSizeLimit = settings.queueSizeLimit;
				data.simUploadLimit = settings.simUploadLimit;
				if (settings.hideButton)   data.hideButton   = true;
				if (settings.fileDesc)     data.fileDesc     = settings.fileDesc;
				if (settings.fileExt)      data.fileExt      = settings.fileExt;
				if (settings.multi)        data.multi        = true;
				if (settings.auto)         data.auto         = true;
				if (settings.sizeLimit)    data.sizeLimit    = settings.sizeLimit;
				if (settings.checkScript)  data.checkScript  = settings.checkScript;
				if (settings.fileDataName) data.fileDataName = settings.fileDataName;
				if (settings.queueID)      data.queueID      = settings.queueID;
				if (settings.onInit() !== false) {
					$(this).css('display','none');
					$(this).after('<div id="' + $(this).attr('id') + 'Uploader"></div>');
					swfobject.embedSWF(settings.uploader, settings.id + 'Uploader', settings.width, settings.height, '9.0.24', settings.expressInstall, data, {'quality':'high','wmode':settings.wmode,'allowScriptAccess':settings.scriptAccess});
					if (settings.queueID == false) {
						$("#" + $(this).attr('id') + "Uploader").after('<div id="' + $(this).attr('id') + 'Queue" class="uploadifyQueue"></div>');
					}
				}
				if (typeof(settings.onOpen) == 'function') {
					$(this).bind("uploadifyOpen", settings.onOpen);
				}
				$(this).bind("uploadifySelect", {'action': settings.onSelect, 'queueID': settings.queueID}, function(event, ID, fileObj) {
					if (event.data.action(event, ID, fileObj) !== false) {
						var byteSize = Math.round(fileObj.size / 1024 * 100) * .01;
						var suffix = 'KB';
						if (byteSize > 1000) {
							byteSize = Math.round(byteSize *.001 * 100) * .01;
							suffix = 'MB';
						}
						var sizeParts = byteSize.toString().split('.');
						if (sizeParts.length > 1) {
							byteSize = sizeParts[0] + '.' + sizeParts[1].substr(0,2);
						} else {
							byteSize = sizeParts[0];
						}
						if (fileObj.name.length > 20) {
							fileName = fileObj.name.substr(0,20) + '...';
						} else {
							fileName = fileObj.name;
						}
						queue = '#' + $(this).attr('id') + 'Queue';
						if (event.data.queueID) {
							queue = '#' + event.data.queueID;
						}
						$(queue).append('<div id="' + $(this).attr('id') + ID + '" class="uploadifyQueueItem">\
								<div class="cancel">\
									<a href="javascript:jQuery(\'#' + jQuery(this).attr('id') + '\').uploadifyCancel(\'' + ID + '\')"><img src="' + settings.cancelImg + '" border="0" /></a>\
								</div>\
								<span class="fileName">' + fileName + ' (' + byteSize + suffix + ')</span><span class="percentage"></span>\
								<div class="uploadifyProgress">\
									<div id="' + jQuery(this).attr('id') + ID + 'ProgressBar" class="uploadifyProgressBar"><!--Progress Bar--></div>\
								</div>\
							</div>');
					}
				});
				if (typeof(settings.onSelectOnce) == 'function') {
					$(this).bind("uploadifySelectOnce", settings.onSelectOnce);
				}
				$(this).bind("uploadifyQueueFull", {'action': settings.onQueueFull}, function(event, queueSizeLimit) {
					if (event.data.action(event, queueSizeLimit) !== false) {
						alert('The queue is full.  The max size is ' + queueSizeLimit + '.');
					}
				});
				$(this).bind("uploadifyCheckExist", {'action': settings.onCheck}, function(event, checkScript, fileQueueObj, folder, single) {
					var postData = new Object();
					postData = fileQueueObj;
					postData.folder = pagePath + folder;
					if (single) {
						for (var ID in fileQueueObj) {
							var singleFileID = ID;
						}
					}
					$.post(checkScript, postData, function(data) {
						for(var key in data) {
							if (event.data.action(event, checkScript, fileQueueObj, folder, single) !== false) {
								var replaceFile = confirm("Do you want to replace the file " + data[key] + "?");
								if (!replaceFile) {
									document.getElementById($(event.target).attr('id') + 'Uploader').cancelFileUpload(key, true,true);
								}
							}
						}
						if (single) {
							document.getElementById($(event.target).attr('id') + 'Uploader').startFileUpload(singleFileID, true);
						} else {
							document.getElementById($(event.target).attr('id') + 'Uploader').startFileUpload(null, true);
						}
					}, "json");
				});
				$(this).bind("uploadifyCancel", {'action': settings.onCancel}, function(event, ID, fileObj, data, clearFast) {
					if (event.data.action(event, ID, fileObj, data, clearFast) !== false) {
						var fadeSpeed = (clearFast == true) ? 0 : 250;
						$("#" + $(this).attr('id') + ID).fadeOut(fadeSpeed, function() { $(this).remove() });
					}
				});
				if (typeof(settings.onClearQueue) == 'function') {
					$(this).bind("uploadifyClearQueue", settings.onClearQueue);
				}
				var errorArray = [];
				$(this).bind("uploadifyError", {'action': settings.onError}, function(event, ID, fileObj, errorObj) {
					if (event.data.action(event, ID, fileObj, errorObj) !== false) {
						var fileArray = new Array(ID, fileObj, errorObj);
						errorArray.push(fileArray);
						$("#" + $(this).attr('id') + ID + " .percentage").text(" - " + errorObj.type + " Error");
						$("#" + $(this).attr('id') + ID).addClass('uploadifyError');
					}
				});
				$(this).bind("uploadifyProgress", {'action': settings.onProgress, 'toDisplay': settings.displayData}, function(event, ID, fileObj, data) {
					if (event.data.action(event, ID, fileObj, data) !== false) {
						$("#" + $(this).attr('id') + ID + "ProgressBar").css('width', data.percentage + '%');
						if (event.data.toDisplay == 'percentage') displayData = ' - ' + data.percentage + '%';
						if (event.data.toDisplay == 'speed') displayData = ' - ' + data.speed + 'KB/s';
						if (event.data.toDisplay == null) displayData = ' ';
						$("#" + $(this).attr('id') + ID + " .percentage").text(displayData);
					}
				});
				$(this).bind("uploadifyComplete", {'action': settings.onComplete}, function(event, ID, fileObj, response, data) {
					if (event.data.action(event, ID, fileObj, unescape(response), data) !== false) {
						$("#" + $(this).attr('id') + ID + " .percentage").text(' - Completed');
						$("#" + $(this).attr('id') + ID).fadeOut(250, function() { $(this).remove()});
					}
				});
				if (typeof(settings.onAllComplete) == 'function') {
					$(this).bind("uploadifyAllComplete", {'action': settings.onAllComplete}, function(event, uploadObj) {
						if (event.data.action(event, uploadObj) !== false) {
							errorArray = [];
						}
					});
				}
			});
		},
		uploadifySettings:function(settingName, settingValue, resetObject) {
			var returnValue = false;
			$(this).each(function() {
				if (settingName == 'scriptData' && settingValue != null) {
					if (resetObject) {
						var scriptData = settingValue;
					} else {
						var scriptData = $.extend(settings.scriptData, settingValue);
					}
					var scriptDataString = '';
					for (var name in scriptData) {
						scriptDataString += '&' + name + '=' + escape(scriptData[name]);
					}
					settingValue = scriptDataString.substr(1);
				}
				returnValue = document.getElementById($(this).attr('id') + 'Uploader').updateSettings(settingName, settingValue);
			});
			if (settingValue == null) {
				if (settingName == 'scriptData') {
					var returnSplit = unescape(returnValue).split('&');
					var returnObj   = new Object();
					for (var i = 0; i < returnSplit.length; i++) {
						var iSplit = returnSplit[i].split('=');
						returnObj[iSplit[0]] = iSplit[1];
					}
					returnValue = returnObj;
				}
				return returnValue;
			}
		},
		uploadifyUpload:function(ID) {
			$(this).each(function() {
				document.getElementById($(this).attr('id') + 'Uploader').startFileUpload(ID, false);
			});
		},
		uploadifyCancel:function(ID) {
			$(this).each(function() {
				document.getElementById($(this).attr('id') + 'Uploader').cancelFileUpload(ID, true, false);
			});
		},
		uploadifyClearQueue:function() {
			$(this).each(function() {
				document.getElementById($(this).attr('id') + 'Uploader').clearFileUploadQueue(false);
			});
		}
	})
})(jQuery);