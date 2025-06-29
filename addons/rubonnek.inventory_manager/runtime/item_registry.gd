#============================================================================
#  item_registry.gd                                                         |
#============================================================================
#                         This file is part of:                             |
#                           INVENTORY MANAGER                               |
#           https://github.com/Rubonnek/inventory-manager                   |
#============================================================================
# Copyright (c) 2024-2025 Wilson Enrique Alvarez Torres                     |
#                                                                           |
# Permission is hereby granted, free of charge, to any person obtaining     |
# a copy of this software and associated documentation files (the           |
# "Software"), to deal in the Software without restriction, including       |
# without limitation the rights to use, copy, modify, merge, publish,       |
# distribute, sublicense, andor sell copies of the Software, and to         |
# permit persons to whom the Software is furnished to do so, subject to     |
# the following conditions:                                                 |
#                                                                           |
# The above copyright notice and this permission notice shall be            |
# included in all copies or substantial portions of the Software.           |
#                                                                           |
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,           |
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF        |
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.    |
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY      |
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,      |
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE         |
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.                    |
#============================================================================

extends RefCounted
class_name ItemRegistry
## Holds a list of items and data the InventoryManager will use to handle them.
##
## Each ItemRegistry must initialized with a set of item IDs provided by the user which can then be used to track item metadata such as item name, description, stack capacity, stack count limit and their metadata.


## Emitted when an item is modified.
signal item_modified(p_item_id : int)

var _m_item_registry_dictionary : Dictionary
var _m_item_registry_entries_dictionary : Dictionary

enum _registry_key {
	ITEM_ENTRIES,
	METADATA,
}

enum _item_entry_key {
	NAME,
	DESCRIPTION,
	ICON,
	STACK_CAPACITY,
	STACK_COUNT_LIMIT,
	METADATA,
}

const DEFAULT_STACK_CAPACITY : int = 99
const DEFAULT_STACK_COUNT_LIMIT : int = 0 # a stack count of 0 means the stack count limit is infinite


## Adds an item to the registry.
func add_item(p_item_id : int, p_name : String = "", p_description : String = "", p_icon : Texture2D = null, p_stack_capacity : int = DEFAULT_STACK_CAPACITY, p_stack_count : int = DEFAULT_STACK_COUNT_LIMIT, p_metadata : Dictionary = {}) -> void:
	if not p_item_id >= 0:
		push_error("ItemRegistry: Unable to add item to registry. The item IDs are required to be greater or equal to 0.")
		return
	if p_stack_capacity <= 0:
		push_error("ItemRegistry: : Attempting to add item ID %d with invalid stack capacity %d. Stack capacity must be a positive integer." % p_item_id, p_stack_capacity)
		return
	if p_stack_count < 0:
		push_error("ItemRegistry: : Attempting to add item ID %d with invalid stack count %d. Stack count must be equal or greater than zero." % p_item_id, p_stack_count)
		return
	if _m_item_registry_entries_dictionary.has(p_item_id):
		push_warning("ItemRegistry: Item ID %d is already registered:\n\n%s\n\nRe-registering will overwrite previous data." % [p_item_id, str(prettify(p_item_id))])

	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if not p_name.is_empty():
		item_registry_entry_dictionary[_item_entry_key.NAME] = p_name
	if not p_description.is_empty():
		item_registry_entry_dictionary[_item_entry_key.DESCRIPTION] = p_description
	if is_instance_valid(p_icon):
		item_registry_entry_dictionary[_item_entry_key.ICON] = p_icon
	if p_stack_capacity != DEFAULT_STACK_CAPACITY:
		item_registry_entry_dictionary[_item_entry_key.STACK_CAPACITY] = p_stack_capacity
	if p_stack_count != DEFAULT_STACK_COUNT_LIMIT:
		item_registry_entry_dictionary[_item_entry_key.STACK_COUNT_LIMIT] = p_stack_count
	if not p_metadata.is_empty():
		item_registry_entry_dictionary[_item_entry_key.METADATA] = p_metadata
	item_modified.emit(p_item_id)


## Removes the item and all the associated data from the registry.
func remove_item(p_item_id : int) -> void:
	var success : bool = _m_item_registry_entries_dictionary.erase(p_item_id)
	if success:
		item_modified.emit(p_item_id)


## Returns true if the item is registered. Returns false otherwise.
func has_item(p_item_id : int) -> bool:
	return _m_item_registry_entries_dictionary.has(p_item_id)


## Sets the item name.
func set_name(p_item_id : int, p_name : String) -> void:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if p_name.is_empty():
		var _success : bool = item_registry_entry_dictionary.erase(_item_entry_key.NAME)
	else:
		item_registry_entry_dictionary[_item_entry_key.NAME] = p_name
	item_modified.emit(p_item_id)


## Returns the item name.
func get_name(p_item_id : int) -> String:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.get(_item_entry_key.NAME, "")


## Returns true if the item has a registered name.
func has_name(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.has(_item_entry_key.NAME)


## Sets the item description.
func set_description(p_item_id : int, p_description : String) -> void:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if p_description.is_empty():
		var _success : bool = item_registry_entry_dictionary.erase(_item_entry_key.DESCRIPTION)
	else:
		item_registry_entry_dictionary[_item_entry_key.DESCRIPTION] = p_description
	item_modified.emit(p_item_id)


## Returns the item description.
func get_description(p_item_id : int) -> String:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.get(_item_entry_key.DESCRIPTION, "")


## Returns true if the item has a description.
func has_description(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.has(_item_entry_key.DESCRIPTION)


## Sets the item icon.
func set_icon(p_item_id : int, p_texture : Texture2D) -> void:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if not is_instance_valid(p_texture):
		var _success : bool = item_registry_entry_dictionary.erase(_item_entry_key.ICON)
	else:
		item_registry_entry_dictionary[_item_entry_key.ICON] = p_texture
	item_modified.emit(p_item_id)


## Returns the item icon. Returns [code]null[/code] if there's none.
func get_icon(p_item_id : int) -> Texture2D:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.get(_item_entry_key.ICON, null)


## Returns true if the item has an icon.
func has_icon(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.has(_item_entry_key.ICON)


## Sets the maximum number of items per stack for the item.
func set_stack_capacity(p_item_id : int, p_stack_capacity : int) -> void:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if p_stack_capacity <= 0:
		push_warning("ItemRegistry: Attempted to set a stack capacity with a negative number which should be positive instead. Ignoring.")
		return
	elif p_stack_capacity == DEFAULT_STACK_CAPACITY:
		var _success : bool = item_registry_entry_dictionary.erase(_item_entry_key.STACK_CAPACITY)
	else:
		item_registry_entry_dictionary[_item_entry_key.STACK_CAPACITY] = p_stack_capacity
	item_modified.emit(p_item_id)


## Returns the stack capacity for the item.
func get_stack_capacity(p_item_id : int) -> int:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.get(_item_entry_key.STACK_CAPACITY, DEFAULT_STACK_CAPACITY)


## Returns true if the item has a stack_capacity different than 99, the default value.
func has_stack_capacity(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.has(_item_entry_key.STACK_CAPACITY)


## Sets the maximum number of stacks for the item.
func set_stack_count_limit(p_item_id : int, p_stack_count : int = 0) -> void:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	if p_stack_count < 0:
		push_warning("ItemRegistry: Attempted to set an invalid stack count. The stack count must be equal or greater than zero. Ignoring.")
		return
	elif p_stack_count == DEFAULT_STACK_COUNT_LIMIT:
		var _success : bool = item_registry_entry_dictionary.erase(_item_entry_key.STACK_COUNT_LIMIT)
	else:
		item_registry_entry_dictionary[_item_entry_key.STACK_COUNT_LIMIT] = p_stack_count
	item_modified.emit(p_item_id)


## Returns the maximum number of items per stack for the item.
func get_stack_count(p_item_id : int) -> int:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	return item_registry_entry_dictionary.get(_item_entry_key.STACK_COUNT_LIMIT, DEFAULT_STACK_COUNT_LIMIT)


## Returns true if the item has a stack count set different than 0, the default value..
func has_stack_count(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		_m_item_registry_entries_dictionary[p_item_id] = item_registry_entry_dictionary
	return item_registry_entry_dictionary.has(_item_entry_key.STACK_COUNT_LIMIT)


## Returns true if the stack count for the item is set to greater than 0. Returns false otherwise.
func is_stack_count_limited(p_item_id : int) -> bool:
	return get_stack_count(p_item_id) > 0


## Returns an array with the registered items.
func keys() -> PackedInt64Array:
	var array : PackedInt64Array = _m_item_registry_entries_dictionary.keys()
	return array


## Attaches the specified metadata to the related item.
func set_item_metadata(p_item_id : int, p_key : Variant, p_value : Variant) -> void:
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		push_error("ItemRegistry: Attempting to set item metadata on unregistered item with id %d. Ignoring call." % p_item_id)
		return
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary[p_item_id]
	var item_metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
	if item_metadata.is_empty():
		item_registry_entry_dictionary[_item_entry_key.METADATA] = item_metadata
	item_metadata[p_key] = p_value
	item_modified.emit(p_item_id)


## Sets the item metadata data.
func set_item_metadata_data(p_item_id : int, p_metadata : Dictionary) -> void:
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		push_error("ItemRegistry: Attempting to set item metadata on unregistered item with id %d. Ignoring call." % p_item_id)
		return
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary[p_item_id]
	item_registry_entry_dictionary[_item_entry_key.METADATA] = p_metadata
	item_modified.emit(p_item_id)


## Returns the specified metadata for the item.
func get_item_metadata(p_item_id : int, p_key : Variant, p_default_value : Variant = null) -> Variant:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	var item_metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
	return item_metadata.get(p_key, p_default_value)


## Returns a reference to the internal metadata dictionary.[br]
## [br]
## [color=yellow]Warning:[/color] Use with caution. Modifying this dictionary will directly modify the installed metadata for the item.
func get_item_metadata_data(p_item_id : int) -> Dictionary:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	var item_metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
	if not _m_item_registry_dictionary.has(_item_entry_key.METADATA):
		# There's a chance the user wants to modify it externally and have it update the ItemRegistry automatically -- make sure we store a reference of that metadata:
		_m_item_registry_dictionary[_item_entry_key.METADATA] = item_metadata
	return item_metadata


## Returns true if the item metadata has the specified key:
func has_item_metadata_key(p_item_id : int, p_key : Variant) -> bool:
	if not _m_item_registry_entries_dictionary.has(p_item_id):
		push_error("ItemRegistry: Attempting to get item metadata on unregistered item with id %d. Returning false." % p_item_id)
		return false
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary[p_item_id]
	var item_metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
	return item_metadata.has(p_key)


## Returns true if the item has some metadata.
func has_item_metadata(p_item_id : int) -> bool:
	var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	var item_metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
	return not item_metadata.is_empty()


## Sets the specified metadata for the item registry.
func set_registry_metadata(p_key : Variant, p_value : Variant) -> void:
	var metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
	metadata[p_key] = p_value
	if not _m_item_registry_dictionary.has(_registry_key.METADATA):
		_m_item_registry_dictionary[_registry_key.METADATA] = metadata
	__sync_registry_metadata_with_debugger()


## Returns the specified metadata from the item registry.
func get_registry_metadata(p_key : Variant, p_default_value : Variant = null) -> Variant:
	var metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
	return metadata.get(p_key, p_default_value)


## Returns a reference to the internal metadata dictionary.
func get_registry_metadata_data() -> Dictionary:
	var metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
	if not _m_item_registry_dictionary.has(_registry_key.METADATA):
		# There's a chance the user wants to modify it externally and have it update the item registry automatically -- make sure we store a reference of that metadata:
		_m_item_registry_dictionary[_registry_key.METADATA] = metadata
	return metadata


## Returns true if the item registry has some metadata.
func has_registry_metadata() -> bool:
	var metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
	return not metadata.is_empty()


## Appends all the items of another item registry.
func append(p_item_registry : ItemRegistry) -> void:
	var registry_data : Dictionary = p_item_registry.get_data()
	var entries_data : Dictionary = registry_data.get(_registry_key.ITEM_ENTRIES, {})
	for item_id : int in entries_data:
		var item_registry_entry_dictionary : Dictionary = entries_data[item_id]
		var name : String = item_registry_entry_dictionary.get(_item_entry_key.NAME, "")
		var description : String = item_registry_entry_dictionary.get(_item_entry_key.DESCRIPTION, "")
		var icon : Texture2D = item_registry_entry_dictionary.get(_item_entry_key.ICON, null)
		var stack_capacity : int = item_registry_entry_dictionary.get(_item_entry_key.STACK_CAPACITY, DEFAULT_STACK_CAPACITY)
		var stack_count : int = item_registry_entry_dictionary.get(_item_entry_key.STACK_COUNT_LIMIT, DEFAULT_STACK_COUNT_LIMIT)
		var metadata : Dictionary = item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
		add_item(item_id, name, description, icon, stack_capacity, stack_count, metadata)


## Returns a reference to the internal dictionary where all the item registry data is stored.[br]
## [br]
## [color=yellow]Warning:[/color] Use with caution. Modifying this dictionary will directly modify the item registry data.
func get_data() -> Dictionary:
	return _m_item_registry_dictionary


## Overwrites the item registry data.
func set_data(p_data : Dictionary) -> void:
	# Track old item IDs:
	var item_ids_changed : Dictionary = _m_item_registry_entries_dictionary

	# Update data
	_m_item_registry_dictionary = p_data
	_m_item_registry_entries_dictionary = _m_item_registry_dictionary[_registry_key.ITEM_ENTRIES]

	# Track new item IDs:
	for item_id : int in _m_item_registry_entries_dictionary:
		item_ids_changed[item_id] = true

	# Send a signal about all the ids that changed:
	for item_id : int in item_ids_changed:
		item_modified.emit(item_id)

	if EngineDebugger.is_active():
		# NOTE: Do not use any of API calls directly here when setting values to avoid sending unnecessary data to the debugger about the duplicated item_registry entry being sent to display

		# Process each entry data
		var duplicated_registry_data : Dictionary = _m_item_registry_dictionary.duplicate(true)
		for item_id : int in duplicated_registry_data:
			# The debugger viewer requires certain objects to be stringified before sending -- duplicate the entry data to avoid overriding the runtime data:
			var duplicated_item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary[item_id]
			duplicated_item_registry_entry_dictionary = duplicated_item_registry_entry_dictionary.duplicate(true)

			# Convert the image into an object that we can send into the debugger
			if duplicated_item_registry_entry_dictionary.has(_item_entry_key.ICON):
				var image : Image = duplicated_item_registry_entry_dictionary[_item_entry_key.ICON]
				duplicated_item_registry_entry_dictionary[_item_entry_key.ICON] = var_to_bytes_with_objects(image)

		# Process the ItemRegistry metadata:
		var metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
		if not metadata.is_empty():
			var stringified_metadata : Dictionary = {}
			for key : Variant in metadata:
				var value : Variant = metadata[key]
				if key is Callable or key is Object:
					stringified_metadata[str(key)] = str(value)
				else:
					stringified_metadata[key] = str(value)
			# Replaced the source metadata with the stringified version that can be displayed remotely:
			duplicated_registry_data[_registry_key.METADATA] = stringified_metadata

		# Send the data
		EngineDebugger.send_message("inventory_manager:item_registry_set_data", [get_instance_id(), duplicated_registry_data])


# Only used by the debugger to inject the data it receives
func __inject(p_item_id : int, p_item_registry_entry_dictionary : Dictionary) -> void:
	if p_item_registry_entry_dictionary.is_empty():
		var _success : bool = _m_item_registry_entries_dictionary.erase(p_item_id)
	else:
		_m_item_registry_entries_dictionary[p_item_id] = p_item_registry_entry_dictionary


func __synchronize_item_data_with_the_debugger(p_item_id : int) -> void:
	if EngineDebugger.is_active():
		# NOTE: Do not use the item_registry API directly here when setting values to avoid sending unnecessary data to the debugger about the duplicated item_registry entry being sent to display

		# The debugger viewer requires certain objects to be stringified before sending -- duplicate the entry data to avoid overriding the runtime data:
		var item_registry_entry_dictionary : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
		var duplicated_item_registry_entry_dictionary : Dictionary = item_registry_entry_dictionary.duplicate(true)

		# Stringify item metadata
		var item_metadata : Dictionary = duplicated_item_registry_entry_dictionary.get(_item_entry_key.METADATA, {})
		if not item_metadata.is_empty():
			var stringified_item_metadata : Dictionary = {}
			for key : Variant in item_metadata:
				var value : Variant = item_metadata[key]
				if key is Callable or key is Object:
					stringified_item_metadata[str(key)] = str(value)
				else:
					stringified_item_metadata[key] = str(value)
			duplicated_item_registry_entry_dictionary[_item_entry_key.METADATA] = stringified_item_metadata

		# Convert the image into an object that we can send into the debugger
		if duplicated_item_registry_entry_dictionary.has(_item_entry_key.ICON):
			var texture : Texture2D = duplicated_item_registry_entry_dictionary[_item_entry_key.ICON]
			var image : Image = texture.get_image()
			duplicated_item_registry_entry_dictionary[_item_entry_key.ICON] = var_to_bytes_with_objects(image)

		var item_registry_manager_id : int = get_instance_id()
		EngineDebugger.send_message("inventory_manager:item_registry_sync_item_registry_entry", [item_registry_manager_id, p_item_id, duplicated_item_registry_entry_dictionary])


## Returns a human-readable dictionary for the item.
func prettify(p_item_id  : int) -> Dictionary:
	var item_data : Dictionary = _m_item_registry_entries_dictionary.get(p_item_id, {})
	var prettified_item_data : Dictionary = item_data.duplicate(true)
	for enum_key : String in _item_entry_key:
		var enum_id : int = _item_entry_key[enum_key]
		if enum_id in prettified_item_data:
			var data : Variant = prettified_item_data[enum_id]
			var _success : bool = prettified_item_data.erase(enum_id)
			prettified_item_data[enum_key.to_snake_case()] = data
	return prettified_item_data


func __sync_registry_metadata_with_debugger() -> void:
	if EngineDebugger.is_active():
		# Stringify registry metadata
		var registry_metadata : Dictionary = _m_item_registry_dictionary.get(_registry_key.METADATA, {})
		registry_metadata = registry_metadata.duplicate(true)
		var stringified_metadata : Dictionary = {}
		for key : Variant in registry_metadata:
			var value : Variant = registry_metadata[key]
			if key is Callable or key is Object:
				stringified_metadata[str(key)] = str(value)
			else:
				stringified_metadata[key] = str(value)

		# Send the stringified metadata
		EngineDebugger.send_message("inventory_manager:item_registry_sync_metadata", [get_instance_id(), stringified_metadata])


func _init() -> void:
	_m_item_registry_dictionary[_registry_key.ITEM_ENTRIES] = _m_item_registry_entries_dictionary
	if EngineDebugger.is_active():
		# Register with the debugger
		EngineDebugger.send_message("inventory_manager:register_item_registry", [get_instance_id()])
		var _success : int = item_modified.connect(__synchronize_item_data_with_the_debugger)
