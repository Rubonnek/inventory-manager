@tool
extends PanelContainer

@export var inventory_manager_viewer_manager_selection_line_edit_ : LineEdit
@export var inventory_manager_viewer_manager_selection_tree_ : Tree
@export var inventory_manager_viewer_item_slots_tree_ : Tree
@export var inventory_manager_viewer_item_slots_view_warning_label_ : Label
@export var inventory_manager_viewer_inventory_data_view_text_edit_ : TextEdit
@export var inventory_manager_viewer_inventory_data_view_warning_label_ : Label

var _m_original_inventory_entry_view_warning_text : String
var _m_original_inventory_data_view_warning_text : String

var _m_remote_item_registry_cache : Dictionary = {}
var _m_remote_inventory_manager_to_its_tree_item_map : Dictionary = {}


func _ready() -> void:
	# Connect InventoryManager tree signals
	var _success : int = inventory_manager_viewer_manager_selection_tree_.item_selected.connect(__on_inventory_manager_selection_tree_item_selected)
	_success = inventory_manager_viewer_manager_selection_tree_.nothing_selected.connect(__on_inventory_manager_selection_tree_nothing_selected)

	# Connect ItemSlot tree signals
	_success = inventory_manager_viewer_item_slots_tree_.item_selected.connect(__on_inventory_view_selection_item_selected)
	_success = inventory_manager_viewer_item_slots_tree_.nothing_selected.connect(__on_inventory_view_selection_nothing_selected)

	# Connect line edit for filtering the InventoryManagers list
	_success = inventory_manager_viewer_manager_selection_line_edit_.text_changed.connect(__on_inventory_manager_selection_line_edit_text_changed)

	# Grab the original metadata warning text -- we'll need this to restore their state once the debugger session is stopped
	_m_original_inventory_entry_view_warning_text = inventory_manager_viewer_item_slots_view_warning_label_.get_text()
	_m_original_inventory_data_view_warning_text = inventory_manager_viewer_inventory_data_view_warning_label_.get_text()

	# Configure the Item Entry Viewer Tree
	inventory_manager_viewer_item_slots_tree_.set_columns(2)
	inventory_manager_viewer_item_slots_tree_.set_column_title(0, "Name")
	inventory_manager_viewer_item_slots_tree_.set_column_title(1, "Amount")
	inventory_manager_viewer_item_slots_tree_.set_column_titles_visible(true)
	inventory_manager_viewer_item_slots_tree_.set_select_mode(Tree.SelectMode.SELECT_ROW)
	inventory_manager_viewer_item_slots_tree_.set_column_title_alignment(0, HORIZONTAL_ALIGNMENT_LEFT)
	inventory_manager_viewer_item_slots_tree_.set_column_title_alignment(1, HORIZONTAL_ALIGNMENT_LEFT)


# ==== EDITOR DEBUGGER PLUGIN PASSTHROUGH FUNCTIONS BEGIN ======
func on_editor_debugger_plugin_capture(p_message : String, p_data : Array) -> bool:
	match p_message:
		"inventory_manager:register_item_registry":
			var item_registry_id : int = p_data[0]
			var item_registry : ItemRegistry = ItemRegistry.new()
			_m_remote_item_registry_cache[item_registry_id] = item_registry
			return true

		"inventory_manager:item_registry_sync_item_registry_entry":
			var item_registry_id : int = p_data[0]
			var item_id : int = p_data[1]
			var item_registry_data : Dictionary = p_data[2]

			# Convert the image bytes back into the image object:
			if item_registry_data.has(ItemRegistry._item_entry_key.ICON):
				var bytes : PackedByteArray = item_registry_data[ItemRegistry._item_entry_key.ICON]
				var image : Image = bytes_to_var_with_objects(bytes)
				image.resize(16,16)
				var texture : ImageTexture = ImageTexture.create_from_image(image)
				item_registry_data[ItemRegistry._item_entry_key.ICON] = texture

			var item_registry : ItemRegistry = _m_remote_item_registry_cache[item_registry_id]
			item_registry.__inject(item_id, item_registry_data)
			return true

		"inventory_manager:item_registry_set_data":
			var item_registry_id : int = p_data[0]
			var item_registry_data : Dictionary = p_data[1]
			var item_registry_entries_data : Dictionary = item_registry_data[ItemRegistry._registry_key.ITEM_ENTRIES]

			# Convert the image bytes back into the image object:
			for item_id : int in item_registry_entries_data:
				var item_registry_entry_data : Dictionary = item_registry_entries_data[item_id]
				if item_registry_entry_data.has(ItemRegistry._item_entry_key.ICON):
					var bytes : PackedByteArray = item_registry_data[ItemRegistry._item_entry_key.ICON]
					var image : Image = bytes_to_var_with_objects(bytes)
					var texture : ImageTexture = ImageTexture.create_from_image(image)
					item_registry_data[ItemRegistry._item_entry_key.ICON] = texture

			var item_registry : ItemRegistry = _m_remote_item_registry_cache[item_registry_id]
			item_registry.set_data(item_registry_data)
			return true

		"inventory_manager:item_registry_sync_metadata":
			var item_registry_id : int = p_data[0]
			var item_registry_metadata : Dictionary = p_data[1]
			var item_registry : ItemRegistry = _m_remote_item_registry_cache[item_registry_id]
			var item_registry_data : Dictionary = item_registry.get_data()
			item_registry_data[ItemRegistry._registry_key.METADATA] = item_registry_metadata
			return true

		"inventory_manager:register_inventory_manager":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_name : String = p_data[1]
			var inventory_manager_path : String = p_data[2]
			var item_registry_id : int = p_data[3]

			# Generate name
			var target_name : String
			if not inventory_manager_name.is_empty():
				target_name = inventory_manager_name
			else:
				if not inventory_manager_path.is_empty():
					target_name = inventory_manager_path.trim_prefix(inventory_manager_path.get_base_dir().path_join("/"))
				else:
					target_name = "Manager"
			target_name = target_name + ":" + String.num_uint64(inventory_manager_id)

			# Create local copy of the InventoryManager
			var item_registry : ItemRegistry = _m_remote_item_registry_cache[item_registry_id]
			var inventory_manager : InventoryManager = InventoryManager.new(item_registry)

			# Create the associated tree_item and add it as metadata against the tree itself so that we can extract it easily when we receive messages from this specific InventoryManager instance id
			var inventory_manager_tree_item : TreeItem = inventory_manager_viewer_manager_selection_tree_.create_item()
			inventory_manager_tree_item.set_text(column, target_name)
			inventory_manager_tree_item.set_metadata(column, inventory_manager)

			# Map the inventory manager instance id to its tree item -- we'll use this later
			_m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id] = inventory_manager_tree_item
			return true


		"inventory_manager:resize":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			var new_size : int = p_data[1]
			var _ignore : Array[ExcessItems] = stored_inventory_manager.resize(new_size)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true

		"inventory_manager:set_data":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			var new_data : Dictionary = p_data[1]
			stored_inventory_manager.set_data(new_data)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true

		"inventory_manager:resize":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			# Resize
			var new_size : int = p_data[1]
			var _ignore : Array[ExcessItems] = stored_inventory_manager.resize(new_size)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true

		"inventory_manager:sync_item_slot":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			# Inject the remote item entry data:
			var remote_item_slot_index : int = p_data[1]
			var remote_item_id : int = p_data[2]
			var remote_item_amount : int = p_data[3]
			stored_inventory_manager.__inject(remote_item_slot_index, remote_item_id, remote_item_amount)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true

		"inventory_manager:clear":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			# Clear
			stored_inventory_manager.clear()

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true


		"inventory_manager:swap":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			# Get the function parameters and execute the action:
			var first_slot : int = p_data[1]
			var second_slot : int = p_data[2]
			stored_inventory_manager.swap(first_slot, second_slot)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true

		"inventory_manager:set_name":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var remote_name : String = p_data[1]
			inventory_manager_tree_item.set_text(column, remote_name)
			return true

		"inventory_manager:organize":
			var column : int = 0
			var inventory_manager_id : int = p_data[0]
			var inventory_manager_tree_item : TreeItem = _m_remote_inventory_manager_to_its_tree_item_map[inventory_manager_id]
			var stored_inventory_manager : InventoryManager = inventory_manager_tree_item.get_metadata(column)

			# Get the function parameters and execute the action:
			var item_ids_array : PackedInt64Array = p_data[1]
			stored_inventory_manager.organize(item_ids_array)

			# Refresh the item entries if needed:
			__refresh_item_slots_if_needed(stored_inventory_manager)
			return true


	push_warning("InventoryManagerViewer: This should not happen. Unmanaged capture: %s %s" % [p_message, p_data])
	return false
# ==== EDITOR DEBUGGER PLUGIN PASSTHROUGH FUNCTIONS ENDS ======


# ===== VISUALIZATION FUNCTIONS BEGIN ====
func __on_session_started() -> void:
	# Clear caches
	_m_remote_item_registry_cache.clear()
	_m_remote_inventory_manager_to_its_tree_item_map.clear()

	# Clear the item manager tree
	inventory_manager_viewer_manager_selection_tree_.clear()
	var _root : TreeItem = inventory_manager_viewer_manager_selection_tree_.create_item() # need to recreate the root TreeItem which gets ignored

	# Clear the item entry tree view
	inventory_manager_viewer_item_slots_tree_.clear()
	inventory_manager_viewer_item_slots_view_warning_label_.set_text("Select an InventoryManager to display its item entries.")
	inventory_manager_viewer_item_slots_view_warning_label_.show()

	# Clear the data view
	inventory_manager_viewer_inventory_data_view_text_edit_.set_text("")
	inventory_manager_viewer_inventory_data_view_warning_label_.set_text("Select a ItemSlot to display its data.")
	inventory_manager_viewer_inventory_data_view_warning_label_.show()

func __on_session_stopped() -> void:
	if not is_instance_valid(inventory_manager_viewer_manager_selection_tree_.get_root()) or inventory_manager_viewer_manager_selection_tree_.get_root().get_child_count() == 0:
		inventory_manager_viewer_item_slots_view_warning_label_.set_text(_m_original_inventory_entry_view_warning_text)


func __on_inventory_manager_selection_line_edit_text_changed(p_filter : String) -> void:
	# Hide the TreeItem that don't match the filter
	var root : TreeItem = inventory_manager_viewer_manager_selection_tree_.get_root()
	var column : int = 0
	for child : TreeItem in root.get_children():
		if p_filter.is_empty() or p_filter in child.get_text(column):
			child.set_visible(true)
		else:
			child.set_visible(false)

	# Select an item (if any):
	inventory_manager_viewer_manager_selection_tree_.deselect_all()
	var did_select_item : bool = false
	for child : TreeItem in root.get_children():
		if child.is_visible():
			inventory_manager_viewer_manager_selection_tree_.set_selected(child, column) # emits item_selected signal
			child.select(column) # highlights the item on the Tree
			did_select_item = true
			break
	if not did_select_item:
		__on_inventory_manager_selection_tree_nothing_selected()


func __on_inventory_manager_selection_tree_nothing_selected() -> void:
	# Deselect
	inventory_manager_viewer_manager_selection_tree_.deselect_all()

	# Clear the item view
	inventory_manager_viewer_item_slots_tree_.clear()
	inventory_manager_viewer_item_slots_view_warning_label_.set_text("Select a InventoryManager to display its item entries.")
	inventory_manager_viewer_item_slots_view_warning_label_.show()

	# Clear the data view
	inventory_manager_viewer_inventory_data_view_text_edit_.set_text("")
	inventory_manager_viewer_inventory_data_view_warning_label_.set_text("Select a ItemSlot to display its data.")
	inventory_manager_viewer_inventory_data_view_warning_label_.show()


func __refresh_item_slots_if_needed(p_updated_inventory_manager : InventoryManager) -> void:
	var selected_tree_item : TreeItem = inventory_manager_viewer_manager_selection_tree_.get_selected()
	if is_instance_valid(selected_tree_item):
		var column : int = 0
		var stored_inventory_manager : InventoryManager = selected_tree_item.get_metadata(column)
		if p_updated_inventory_manager == stored_inventory_manager:
			__refresh_item_slots()


func __refresh_item_slots() -> void:
	# Populate item entries

	# Update item view warning label:
	if inventory_manager_viewer_item_slots_view_warning_label_.is_visible():
		inventory_manager_viewer_item_slots_view_warning_label_.hide()

	# Grab the selected tree item and item manager:
	var inventory_manager_selected_tree_item : TreeItem = inventory_manager_viewer_manager_selection_tree_.get_selected()
	var item_name_column : int = 0
	var inventory_manager : InventoryManager = inventory_manager_selected_tree_item.get_metadata(item_name_column)

	# Clear the item selection tree as well
	var selected_item_slot_id : int = -1 # -1 is used as a sentinel value -- item IDs begin at 0
	if inventory_manager_viewer_item_slots_tree_.has_meta(&"item_slot_id_to_tree_item_map"):
		var inventory_entry_selected_tree_item : TreeItem = inventory_manager_viewer_item_slots_tree_.get_selected()
		if is_instance_valid(inventory_entry_selected_tree_item):
			var previous_item_slot_id_to_tree_item_map : Dictionary = inventory_manager_viewer_item_slots_tree_.get_meta(&"item_slot_id_to_tree_item_map")
			selected_item_slot_id = previous_item_slot_id_to_tree_item_map.find_key(inventory_entry_selected_tree_item)
	inventory_manager_viewer_item_slots_tree_.clear()
	var _root : TreeItem = inventory_manager_viewer_item_slots_tree_.create_item()

	# Traverse all item entries and add them to the tree:
	var item_slot_id_to_tree_item_map : Dictionary = {}
	var item_name_title_alignment : HorizontalAlignment = inventory_manager_viewer_item_slots_tree_.get_column_title_alignment(0)
	var item_amount_title_alignment : HorizontalAlignment = inventory_manager_viewer_item_slots_tree_.get_column_title_alignment(1)
	var item_amount_column : int = 1
	for slot_number : int in inventory_manager.slots():
		if inventory_manager.__is_slot_empty(slot_number):
			continue

		# Create the associated tree item and configure it
		var inventory_tree_item : TreeItem = inventory_manager_viewer_item_slots_tree_.create_item()

		var item_id : int = inventory_manager.__get_slot_item_id(slot_number)
		var item_registry : ItemRegistry = inventory_manager.get_item_registry()

		# Install the item icon:
		var texture : Texture2D = item_registry.get_icon(item_id)
		if is_instance_valid(texture):
			inventory_tree_item.set_icon(item_name_column, texture)


		# Install the item tooltip:
		var tooltip_string : String = ""
		tooltip_string += "Slot: %d\n" % slot_number
		tooltip_string += "Item ID: %d\n" % inventory_manager.__get_slot_item_id(slot_number)
		var item_name : String = item_registry.get_name(item_id)
		if item_name.is_empty():
			item_name = "(Empty Item Name)"
		tooltip_string += "Name: %s\n" % item_name
		var item_description : String = item_registry.get_description(item_id)
		if item_description.is_empty():
			item_description = "(Empty Item Description)"
		tooltip_string += "Description: %s\n" % item_description
		tooltip_string += "Amount: %d\n" % inventory_manager.__get_slot_item_amount(slot_number)
		tooltip_string += "Stack Size: %d\n" % item_registry.get_stack_capacity(item_id)
		var amount : int = inventory_manager.__get_slot_item_amount(slot_number)
		inventory_tree_item.set_text(item_name_column, item_name)
		inventory_tree_item.set_text(item_amount_column, str(amount))
		inventory_tree_item.set_text_alignment(item_name_column, item_name_title_alignment)
		inventory_tree_item.set_text_alignment(item_amount_column, item_amount_title_alignment)
		inventory_tree_item.set_tooltip_text(item_name_column, tooltip_string.strip_edges(true, true))

		# Store the item manager and item ID on its tree item so that we can retrieve its data easily later.
		var inventory_tree_item_metadata : Array = [inventory_manager, slot_number]
		inventory_tree_item.set_metadata(item_name_column, inventory_tree_item_metadata)

		# Also map the item id to their tree items - we need to to refresh the item data view if needed
		item_slot_id_to_tree_item_map[slot_number] = inventory_tree_item

	# Store the item_slot_id_to_tree_item_map -- this will be needed the next time we refresh the item entries
	if selected_item_slot_id >= 0:
		if item_slot_id_to_tree_item_map.has(selected_item_slot_id):
			var tree_item_to_select : TreeItem = item_slot_id_to_tree_item_map[selected_item_slot_id]
			tree_item_to_select.select(item_name_column)
		else:
			__on_inventory_view_selection_nothing_selected()


func __on_inventory_manager_selection_tree_item_selected() -> void:
	var selected_tree_item : TreeItem = inventory_manager_viewer_manager_selection_tree_.get_selected()
	if is_instance_valid(selected_tree_item):
		__refresh_item_slots()


func __on_inventory_view_selection_nothing_selected() -> void:
	if inventory_manager_viewer_item_slots_tree_.get_selected_column() != -1:
		# Deselect the item
		inventory_manager_viewer_item_slots_tree_.deselect_all()

		# Clear the data view
		inventory_manager_viewer_inventory_data_view_text_edit_.set_text("")
		inventory_manager_viewer_inventory_data_view_warning_label_.set_text("Select a ItemSlot to display its data.")
		inventory_manager_viewer_inventory_data_view_warning_label_.show()


func __on_inventory_view_selection_item_selected() -> void:
	var selected_tree_item : TreeItem = inventory_manager_viewer_item_slots_tree_.get_selected()
	if is_instance_valid(selected_tree_item):
		if inventory_manager_viewer_inventory_data_view_warning_label_.is_visible():
			inventory_manager_viewer_inventory_data_view_warning_label_.hide()

		var column : int = 0
		var inventory_tree_item_metadata : Array = selected_tree_item.get_metadata(column)
		var inventory_manager : InventoryManager = inventory_tree_item_metadata[0]
		var slot_number : int = inventory_tree_item_metadata[1]


		var item_id : int = inventory_manager.__get_slot_item_id(slot_number)
		var item_registry : ItemRegistry = inventory_manager.get_item_registry()

		# Update the data view
		var data_view : String = ""
		data_view += "Slot: %d\n" % slot_number
		data_view += "Item ID: %d\n" % inventory_manager.__get_slot_item_id(slot_number)
		var item_name : String = item_registry.get_name(item_id)
		if item_name.is_empty():
			item_name = "(Empty Item Name)"
		data_view += "Name: %s\n" % item_name
		var item_description : String = item_registry.get_description(item_id)
		if item_description.is_empty():
			item_description = "(Empty Item Description)"
		data_view += "Description: %s\n" % item_description
		data_view += "Amount: %d\n" % inventory_manager.__get_slot_item_amount(slot_number)
		data_view += "Stack Size: %d\n" % item_registry.get_stack_capacity(item_id)
		if item_registry.has_item_metadata(item_id):
			var item_metadata : Dictionary = item_registry.get_item_metadata_data(item_id)
			data_view += "Item Metadata:\n%s\n" % JSON.stringify(item_metadata, "\t")

		inventory_manager_viewer_inventory_data_view_text_edit_.set_text(data_view.strip_edges(true,true))
# ===== VISUALIZATION FUNCTIONS END ====
