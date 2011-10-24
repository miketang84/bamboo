/**
 * @author ZhangHuihua@msn.com
 */
(function($){
	var _lookup = {currentGroup:"",currentName:"",index:-1};
	var _util = {
		_lookupPrefix: function(){
			var indexStr = _lookup.index < 0 ? "" : "["+_lookup.index+"]";
			var preFix = _lookup.currentGroup + indexStr;
			return preFix ? preFix+"." : "";
		},
		lookupPk: function(key){
			return _util._lookupPrefix() + _lookup.currentName + "." + key;
		},
		lookupField: function(key){
			return _util._lookupPrefix() + "dwz_" + _lookup.currentName + "." + key;
		}
	};
	
	$.extend({
		bringBackSuggest: function(args, targetType){
			var $box = targetType == "dialog" ? $.pdialog.getCurrent() : navTab.getCurrentPanel();
			$box.find(":input").each(function(){
				var $input = $(this), inputName = $input.attr("name");
				
				for (var key in args) {
					var name = ("id" == key) ? _util.lookupPk(key) : _util.lookupField(key);
					if (name == inputName) {
						$input.val(args[key]);
						break;
					}
				}
			});
		},
		bringBack: function(args, targetType){
			$.bringBackSuggest(args, targetType);
			$.pdialog.closeCurrent();
		}
	});
	
	$.fn.extend({
		lookup: function(){
			return this.each(function(){
				var $this = $(this), options = {mask:true, 
					width:$this.attr('width')||820, height:$this.attr('height')||400,
					maxable:eval($this.attr("maxable") || "true"),
					resizable:eval($this.attr("resizable") || "true")
				};
				$this.click(function(event){
					_lookup = $.extend(_lookup, {
						currentGroup: $this.attr("lookupGroup") || "", 
						currentName:$this.attr("lookupName") || "",
						index: parseInt($this.attr("index")|| -1)
					});
					$.pdialog.open($this.attr("href"), "_blank", $this.attr("title") || $this.text(), options);
					return false;
				});
			});
		},
		suggest: function(){
			var op = {suggest$:"#suggest", suggestShadow$: "#suggestShadow"};
			var selectedIndex = -1;
			return this.each(function(){
				var $input = $(this).attr('autocomplete', 'off').keydown(function(event){
					if (event.keyCode == DWZ.keyCode.ENTER) return false; //屏蔽回车提交
				});
				
				var suggestFields=$input.attr('suggestFields').split(",");
				
				function _show(){
					var offset = $input.offset();
					var iTop = offset.top+this.offsetHeight;
					var $suggest = $(op.suggest$);
					if ($suggest.size() == 0) $suggest = $('<div id="suggest"></div>').appendTo($('body'));

					$suggest.css({
						left:offset.left+'px',
						top:iTop+'px'
					}).show();
					
					_lookup = $.extend(_lookup, {
						currentGroup: $input.attr("lookupGroup") || "", 
						currentName:$input.attr("lookupName") || "",
						index: parseInt($input.attr("index")|| -1)
					});

					$.ajax({
						type:'POST', dataType:"json", url:$input.attr("suggestUrl"), cache: false,
						data:{inputValue:$input.val()},
						success: function(response){
							if (!response) return;
							var html = '';

							$.each(response, function(i){
								var liAttr = '', liLabel = '';
								
								for (var i=0; i<suggestFields.length; i++){
									var str = this[suggestFields[i]];
									if (str) {
										if (liLabel) liLabel += '-';
										liLabel += str;
										if (liAttr) liAttr += ',';
										liAttr += suggestFields[i]+":'"+str+"'";
									}
								}
								html += '<li lookupId="'+this["id"]+'" lookupAttrs="'+liAttr+'">' + liLabel + '</li>';
							});
							$suggest.html('<ul>'+html+'</ul>').find("li").hoverClass("selected").click(function(){
								_select($(this));
							});
						},
						error: function(){
							$suggest.html('');
						}
					});

					$(document).bind("click", _close);
					return false;
				}
				function _select($item){
					var jsonStr = "{id:'"+$item.attr('lookupId')+"'," + $item.attr('lookupAttrs') +"}";
					$.bringBackSuggest(DWZ.jsonEval(jsonStr));
				}
				function _close(){
					$(op.suggest$).html('').hide();
					selectedIndex = -1;
					$(document).unbind("click", _close);
				}
				
				$input.focus(_show).click(false).keyup(function(event){
					var $items = $(op.suggest$).find("li");
					switch(event.keyCode){
						case DWZ.keyCode.ESC:
						case DWZ.keyCode.TAB:
						case DWZ.keyCode.SHIFT:
						case DWZ.keyCode.HOME:
						case DWZ.keyCode.END:
						case DWZ.keyCode.LEFT:
						case DWZ.keyCode.RIGHT:
							break;
						case DWZ.keyCode.ENTER:
							_close();
							break;
						case DWZ.keyCode.DOWN:
							if (selectedIndex >= $items.size()-1) selectedIndex = -1;
							else selectedIndex++;
							break;
						case DWZ.keyCode.UP:
							if (selectedIndex < 0) selectedIndex = $items.size()-1;
							else selectedIndex--;
							break;
						default:
							_show();
					}
					$items.removeClass("selected");
					if (selectedIndex>=0) {
						var $item = $items.eq(selectedIndex).addClass("selected");
						_select($item);
					}
				});
			});
		},
		
		itemDetail: function(){
			return this.each(function(){
				var $table = $(this).css("clear","both"), $tbody = $table.find("tbody");
				var itemDetail = $table.attr("itemDetail") || "", fields=[];

				$table.find("tr:first th[type]").each(function(){
					var $th = $(this);
					var field = {
						type: $th.attr("type") || "text",
						patternDate: $th.attr("format") || "yyyy-MM-dd",
						name: $th.attr("name") || "",
						size: $th.attr("size") || "12",
						enumName: $th.attr("enumName") || "",
						enumUrl: $th.attr("enumUrl") || "",
						lookupName: $th.attr("lookupName") || "",
						lookupUrl: $th.attr("lookupUrl") || "",
						suggestUrl: $th.attr("suggestUrl"),
						suggestFields: $th.attr("suggestFields"),
						fieldClass: $th.attr("fieldClass") || ""
					};
					fields.push(field);
				});
				
				$tbody.find("a.btnDel").click(function(){
					var $btnDel = $(this);
					function delDbData(){
						$.ajax({
							type:'POST', dataType:"json", url:$btnDel.attr('href'), cache: false,
							success: function(){
								$btnDel.parents("tr:first").remove();
								initSuffix($tbody);
							},
							error: DWZ.ajaxError
						});
					}
					
					if ($btnDel.attr("title")){
						alertMsg.confirm($btnDel.attr("title"), {okCall: delDbData});
					} else {
						delDbData();
					}
					
					return false;
				});

				var addButTxt = $table.attr('addButton') || "Add New";
				if (addButTxt) {
					var $addBut = $('<div class="button"><div class="buttonContent"><button type="button">'+addButTxt+'</button></div></div>').insertBefore($table).find("button");
					var $rowNum = $('<input type="text" name="dwz_rowNum" class="textInput" style="margin:2px;" value="1" size="2"/>').insertBefore($table);
					
					var trTm = "";
					$addBut.click(function(){
						if (! trTm) trTm = trHtml(fields, itemDetail);
						var rowNum = 1;
						try{rowNum = parseInt($rowNum.val())} catch(e){}
	
						for (var i=0; i<rowNum; i++){
							var $tr = $(trTm.replaceAll("#index#", $tbody.find(">tr").size()));
							$tr.appendTo($tbody).initUI().find("a.btnDel").click(function(){
								$(this).parents("tr:first").remove();
								initSuffix($tbody);
								return false;
							});
						}
					});
				}
			});
			
			/**
			 * 删除时重新初始化下标
			 */
			function initSuffix($tbody) {
				$tbody.find('>tr').each(function(i){
					$(':input', this).each(function(){
						var $input = $(this);
						var name = $input.attr('name').replaceAll('\[[0-9]+\]','['+i+']');
						$input.attr('name', name);
					});
				});
			}
			function tdHtml(field, itemDetail){
				var html = '', fieldName = itemDetail+'[#index#].'+field.name;
				var lookupFieldName = itemDetail+'[#index#].dwz_'+field.lookupName+'.'+field.name;
				switch(field.type){
					case 'del':
						html = '<a href="javascript:void(0)" class="btnDel '+ field.fieldClass + '">删除</a>';
						break;
					case 'lookup':
						var suggestFrag = '';
						if (field.suggestFields) {
							suggestFrag = 'autocomplete="off" lookupGroup="'+itemDetail+'" lookupName="'+field.lookupName+'" index="#index#" suggestUrl="'+field.suggestUrl+'" suggestFields="'+field.suggestFields+'"';
						}

						html = '<input type="hidden" name="'+itemDetail+'[#index#].'+field.lookupName+'.id"/>'
							+ '<input type="text" name="'+lookupFieldName+'"'+suggestFrag+' size="'+field.size+'" class="'+field.fieldClass+'"/>'
							+ '<a class="btnLook" href="'+field.lookupUrl+'" lookupGroup="'+itemDetail+'" lookupName="'+field.lookupName+'" index="#index#" title="查找带回">查找带回</a>';
						break;
					case 'lookupField':
						html = '<input type="text" name="'+lookupFieldName+'" size="'+field.size+'" class="'+field.fieldClass+'" readonly="readonly"/>';
						break;
					case 'attach':
						html = '<input type="hidden" name="'+itemDetail+'[#index#].'+field.lookupName+'.id"/>'
							+ '<input type="text" name="'+lookupFieldName+'" size="'+field.size+'" readonly="readonly" class='+field.fieldClass+'"/>'
							+ '<a class="btnAttach" href="'+field.lookupUrl+'" lookupGroup="'+itemDetail+'" lookupName="'+field.lookupName+'" index="#index#" width="560" height="300" title="查找带回">查找带回</a>';
						break;
					case 'enum':
						$.ajax({
							type:"POST", dataType:"html", async: false,
							url:field.enumUrl, 
							data:{enumName:field.enumName, inputName:fieldName}, 
							success:function(response){
								html = response;
							}
						});
						break;
					case 'date':
						html = '<input type="text" name="'+fieldName+'" class="date '+field.fieldClass+'" format="'+field.patternDate+'" size="'+field.size+'"/>'
							+'<a class="inputDateButton" href="javascript:void(0)">选择</a>';
						break;
					default:
						html = '<input type="text" name="'+fieldName+'" size="'+field.size+'" class="'+field.fieldClass+'"/>';
						break;
				}
				return '<td>'+html+'</td>';
			}
			function trHtml(fields, itemDetail){
				var html = '';
				$(fields).each(function(){
					html += tdHtml(this, itemDetail);
				});
				return "<tr>"+html+"</tr>";
			}
		},
		
		selectedTodo: function(){
			
			function _getIds(selectedIds, targetType){
				var ids = "";
				var $box = targetType == "dialog" ? $.pdialog.getCurrent() : navTab.getCurrentPanel();
				$box.find("input:checked").filter("[name='"+selectedIds+"']").each(function(i){
					var val = $(this).val();
					ids += i==0 ? val : ","+val;
				});
				return ids;
			}
			return this.each(function(){
				var $this = $(this);
				var selectedIds = $this.attr("rel") || "ids";
				var postType = $this.attr("postType") || "map";

				$this.click(function(){
					var ids = _getIds(selectedIds, $this.attr("targetType"));
					if (!ids) {
						alertMsg.error($this.attr("warn") || DWZ.msg("alertSelectMsg"));
						return false;
					}
					function _doPost(){
						$.ajax({
							type:'POST', url:$this.attr('href'), dataType:'json', cache: false,
							data: function(){
								if (postType == 'map'){
									return $.map(ids.split(','), function(val, i) {
										return {name: selectedIds, value: val};
									})
								} else {
									var _data = {};
									_data[selectedIds] = ids;
									return _data;
								}
							}(),
							success: navTabAjaxDone,
							error: DWZ.ajaxError
						});
					}
					var title = $this.attr("title");
					if (title) {
						alertMsg.confirm(title, {okCall: _doPost});
					} else {
						_doPost();
					}
					return false;
				});
				
			});
		}
	});
})(jQuery);

