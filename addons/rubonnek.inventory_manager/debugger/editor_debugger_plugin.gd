@tool
extends EditorDebuggerPlugin


var session_id_to_inventory_manager_viewer : Dictionary = {}


func _setup_session(p_session_id : int) -> void:
	# Instantiate the inventory manager viewer and grab the debugger session
	var inventory_manager_viewer : Control = preload("./inventory_manager_viewer.tscn").instantiate()
	var editor_debugger_session : EditorDebuggerSession = get_session(p_session_id)

	# Listen to the debugger session started signal.
	@warning_ignore("unsafe_property_access", "unsafe_call_argument")
	var _success : int = editor_debugger_session.started.connect(inventory_manager_viewer.__on_session_started)
	@warning_ignore("unsafe_property_access", "unsafe_call_argument")
	_success = editor_debugger_session.stopped.connect(inventory_manager_viewer.__on_session_stopped)

	# Add the inventory manager viewer to the debugger tabs
	editor_debugger_session.add_session_tab(inventory_manager_viewer)

	# Track sessions so that we can push the data from _capture into the right session
	session_id_to_inventory_manager_viewer[p_session_id] = inventory_manager_viewer


func _has_capture(p_prefix : String) -> bool:
	return p_prefix == "inventory_manager"


func _capture(p_message : String, p_data : Array, p_session_id : int) -> bool:
	var inventory_manager_viewer : Control = session_id_to_inventory_manager_viewer[p_session_id]
	@warning_ignore("unsafe_method_access")
	return inventory_manager_viewer.on_editor_debugger_plugin_capture(p_message, p_data)
