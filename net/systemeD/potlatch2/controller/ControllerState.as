package net.systemeD.potlatch2.controller {
	import flash.events.*;
	import flash.display.*;
    import net.systemeD.halcyon.Map;
    import net.systemeD.halcyon.MapPaint;
    import net.systemeD.halcyon.connection.*;
    import net.systemeD.potlatch2.collections.Imagery;
    import net.systemeD.potlatch2.EditController;
	import net.systemeD.potlatch2.save.SaveManager;
	import net.systemeD.potlatch2.utils.SnapshotConnection;
	import flash.ui.Keyboard;
	import mx.controls.Alert;
	import mx.events.CloseEvent;
	
    /** Represents a particular state of the controller, such as "dragging a way" or "nothing selected". Key methods are 
    * processKeyboardEvent and processMouseEvent which take some action, and return a new state for the controller. 
    * 
    * This abstract class has some behaviour that applies in most states, and lots of 'null' behaviour. 
    * */
    public class ControllerState {

        protected var controller:EditController;
		public var layer:MapPaint;
        protected var previousState:ControllerState;

		protected var _selection:Array=[];

        public function ControllerState() {}

        public function setController(controller:EditController):void {
            this.controller=controller;
            if (!layer) layer=controller.map.editableLayer;
        }

        public function setPreviousState(previousState:ControllerState):void {
            if ( this.previousState == null )
                this.previousState = previousState;
        }

		public function isSelectionState():Boolean {
			return true;
		}

        /** When triggered by a mouse action such as a click, perform an action on the given entity, then move to a new state. */
        public function processMouseEvent(event:MouseEvent, entity:Entity):ControllerState {
            return this;
        }
		
		/** When triggered by a keypress, perform an action on the given entity, then move to a new state. */
        public function processKeyboardEvent(event:KeyboardEvent):ControllerState {
            return this;
        }

        /** Retrieves the map associated with the current EditController */
		public function get map():Map {
			return controller.map;
		}

        /** This is called when the EditController sets this ControllerState as the active state.
        * Override this with whatever is needed, such as adding highlights to entities
        */
        public function enterState():void {}

        /** This is called by the EditController as the current controllerstate is exiting.
        * Override this with whatever cleanup is needed, such as removing highlights from entities
        */
        public function exitState(newState:ControllerState):void {}

		/** Represent the state in text for debugging. */
		public function toString():String {
			return "(No state)";
		}
		/** Default behaviour for the current state that should be called if state-specific action has been taken care of or ruled out. */
		protected function sharedKeyboardEvents(event:KeyboardEvent):ControllerState {
			var editableLayer:MapPaint=controller.map.editableLayer;								// shorthand for this method
			switch (event.keyCode) {
				case 66:	setSourceTag(); break;													// B - set source tag for current object
				case 67:	editableLayer.connection.closeChangeset(); break;						// C - close changeset
				case 68:	editableLayer.alpha=1.3-editableLayer.alpha; return null;				// D - dim
				case 83:	SaveManager.saveChanges(editableLayer.connection); break;				// S - save
				case 84:	controller.tagViewer.togglePanel(); return null;						// T - toggle tags panel
				case 90:	if (!event.shiftKey) { MainUndoStack.getGlobalStack().undo(); return null;}// Z - undo
				            else { MainUndoStack.getGlobalStack().redo(); return null;  }           // Shift-Z - redo 						
				case Keyboard.ESCAPE:	revertSelection(); break;									// ESC - revert to server version
				case Keyboard.NUMPAD_ADD:															// + - add tag
				case 187:	controller.tagViewer.selectAdvancedPanel();								//   |
							controller.tagViewer.addNewTag(); return null;							//   |
			}
			return null;
		}

		/** Default behaviour for the current state that should be called if state-specific action has been taken care of or ruled out. */
		protected function sharedMouseEvents(event:MouseEvent, entity:Entity):ControllerState {
			var paint:MapPaint = getMapPaint(DisplayObject(event.target));
            var focus:Entity = getTopLevelFocusEntity(entity);

			if ( event.type == MouseEvent.MOUSE_UP && focus && map.dragstate!=map.NOT_DRAGGING) {
				map.mouseUpHandler();	// in case the end-drag is over an EntityUI
			} else if ( event.type == MouseEvent.ROLL_OVER && paint && paint.interactive ) {
				paint.setHighlight(focus, { hover: true });
			} else if ( event.type == MouseEvent.MOUSE_OUT && paint && paint.interactive ) {
				paint.setHighlight(focus, { hover: false });
			} else if ( event.type == MouseEvent.MOUSE_WHEEL ) {
				if      (event.delta > 0) { map.zoomIn(); }
				else if (event.delta < 0) { map.zoomOut(); }
			}

			if ( paint && paint.isBackground ) {
				if (event.type == MouseEvent.MOUSE_DOWN && ((event.shiftKey && event.ctrlKey) || event.altKey) ) {
					// alt-click to pull data out of vector background layer
					var newSelection:Array=[];
					if (selection.indexOf(entity)==-1) { selection=[entity]; }
					for each (var entity:Entity in selection) {
						paint.setHighlight(entity, { hover:false, selected: false });
						if (entity is Way) paint.setHighlightOnNodes(Way(entity), { selectedway: false });
						newSelection.push(paint.pullThrough(entity,controller.map.editableLayer));
					}
					return controller.findStateForSelection(newSelection);
				} else if (!paint.interactive) {
					return null;
				} else if (event.type == MouseEvent.MOUSE_DOWN && paint.interactive) {
					if      (entity is Way   ) { return new SelectedWay(entity as Way, paint); }
					else if (entity is Node  ) { if (!entity.hasParentWays) return new SelectedPOINode(entity as Node, paint); }
					else if (entity is Marker) { return new SelectedMarker(entity as Marker, paint); }
				} else if ( event.type == MouseEvent.MOUSE_UP && !event.ctrlKey) {
					return (this is NoSelection) ? null : new NoSelection();
				} else if ( event.type == MouseEvent.CLICK && focus == null && map.dragstate!=map.DRAGGING && !event.ctrlKey) {
					return (this is NoSelection) ? null : new NoSelection();
				}
					
			} else if ( event.type == MouseEvent.MOUSE_DOWN ) {
				if ( entity is Node && selectedWay && entity.hasParent(selectedWay) ) {
					// select node within this way
					return new DragWayNode(selectedWay,  getNodeIndex(selectedWay,entity as Node),  event, false);
				} else if ( controller.keyDown(Keyboard.SPACE) ) {
					// drag the background imagery to compensate for poor alignment
					return new DragBackground(event);
				} else if (entity && selection.indexOf(entity)>-1) {
					return new DragSelection(selection, event);
				} else if (entity) {
					return controller.findStateForSelection([entity]);
				} else if (event.ctrlKey && !layer.isBackground) {
					return new SelectArea(event.localX,event.localY,selection);
				}

            } else if ( event.type==MouseEvent.MOUSE_UP && focus == null && map.dragstate!=map.DRAGGING && !event.ctrlKey) {
                return (this is NoSelection) ? null : new NoSelection();
            }
			return null;
		}

		/** Gets the way that the selected node is part of, if that makes sense. If not, return the node, or the way, or nothing. */
		public static function getTopLevelFocusEntity(entity:Entity):Entity {
			if ( entity is Node ) {
				for each (var parent:Entity in entity.parentWays) {
					return parent;
				}
				return entity;
			} else if ( entity is Way ) {
				return entity;
			} else {
				return null;
			}
		}

		/** Find the MapPaint object that this DisplayObject belongs to. */
		protected function getMapPaint(d:DisplayObject):MapPaint {
			while (d) {
				if (d is MapPaint) { return MapPaint(d); }
				d=d.parent;
			}
			return null;
		}

		protected function getNodeIndex(way:Way,node:Node):uint {
			for (var i:uint=0; i<way.length; i++) {
				if (way.getNode(i)==node) { return i; }
			}
			return null;
		}

		/** Create a "repeat tags" action on the current entity, if possible. */
		protected function repeatTags(object:Entity):void {
			if (!controller.clipboards[object.getType()]) { return; }
			object.suspend();

		    var undo:CompositeUndoableAction = new CompositeUndoableAction("Repeat tags");
			for (var k:String in controller.clipboards[object.getType()]) {
				object.setTag(k, controller.clipboards[object.getType()][k], undo.push)
			}
			MainUndoStack.getGlobalStack().addAction(undo);
                        controller.updateSelectionUI();
			object.resume();


		}

		/** Create an action to add "source=*" tag to current entity based on background imagery. This is a convenient shorthand for users. */
		protected function setSourceTag():void {
			if (selectCount!=1) { return; }
			if (Imagery.instance().selected && Imagery.instance().selected.sourcetag) {
				if ("sourcekey" in Imagery.instance().selected)
				    firstSelected.setTag(Imagery.instance().selected.sourcekey,Imagery.instance().selected.sourcetag, MainUndoStack.getGlobalStack().addAction);
				else
				    firstSelected.setTag('source',Imagery.instance().selected.sourcetag, MainUndoStack.getGlobalStack().addAction);
			}
			controller.updateSelectionUI();
		}

		/** Revert all selected items to previously saved state, via a dialog box. */
		protected function revertSelection():void {
			if (selectCount==0) return;
			Alert.show("Revert selected items to the last saved version, discarding your changes?","Are you sure?",Alert.YES | Alert.CANCEL,null,revertHandler);
		}
		protected function revertHandler(event:CloseEvent):void {
			if (event.detail==Alert.CANCEL) return;
			for each (var item:Entity in _selection) {
				item.connection.loadEntity(item);
			}
		}

		// Selection getters

		public function get selectCount():uint {
			return _selection.length;
		}

		public function get selection():Array {
			return _selection;
		}

		public function get firstSelected():Entity {
			if (_selection.length==0) { return null; }
			return _selection[0];
		}

		public function get selectedWay():Way {
			if (firstSelected is Way) { return firstSelected as Way; }
			return null;
		}

		public function get selectedWays():Array {
			var selectedWays:Array=[];
			for each (var item:Entity in _selection) {
				if (item is Way) { selectedWays.push(item); }
			}
			return selectedWays;
		}

        public function get selectedNodes():Array {
            var selectedNodes:Array=[];
            for each (var item:Entity in _selection) {
                if (item is Node) { selectedNodes.push(item); }
            }
            return selectedNodes;
        }

		public function hasSelectedWays():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way) { return true; }
			}
			return false;
		}

		public function hasSelectedAreas():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way && Way(item).isArea()) { return true; }
			}
			return false;
		}

		public function hasSelectedUnclosedWays():Boolean {
			for each (var item:Entity in _selection) {
				if (item is Way && !Way(item).isArea()) { return true; }
			}
			return false;
		}

        /** Determine whether or not any nodes are selected, and if so whether any of them belong to areas. */
        public function hasSelectedWayNodesInAreas():Boolean {
            for each (var item:Entity in _selection) {
                if (item is Node) {
                    var parentWays:Array = Node(item).parentWays;
                    for each (var way:Entity in parentWays) {
                        if (Way(way).isArea()) { return true; }
                    }
                }
            }
            return false;
        }

		public function hasAdjoiningWays():Boolean {
			if (_selection.length<2) { return false; }
			var endNodes:Object={};
			for each (var item:Entity in _selection) {
				if (item is Way && !Way(item).isArea()) {
					if (endNodes[Way(item).getNode(0).id]) return true;
					if (endNodes[Way(item).getLastNode().id]) return true;
					endNodes[Way(item).getNode(0).id]=true;
					endNodes[Way(item).getLastNode().id]=true;
				}
			}
			return false;
		}

		// Selection setters

		public function set selection(items:Array):void {
			_selection=items;
		}

		public function addToSelection(items:Array):void {
			for each (var item:Entity in items) {
				if (_selection.indexOf(item)==-1) { _selection.push(item); }
			}
		}

		public function removeFromSelection(items:Array):void {
			for each (var item:Entity in items) {
				if (_selection.indexOf(item)>-1) {
					_selection.splice(_selection.indexOf(item),1);
				}
			}
		}

		public function toggleSelection(item:Entity):Boolean {
			if (_selection.indexOf(item)==-1) {
				_selection.push(item); return true;
			}
			_selection.splice(_selection.indexOf(item),1); return false;
		}
    }
}
