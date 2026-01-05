extends Control

enum item_ids {
	HEALTH_POTION,
}


func _ready() -> void:
	# There are two ways of creating an infinite inventory for a specific item.

	# The first way is setting the stack capacity to a very high number,
	# which is the most perfomant way, but if the value is taken as-is it might mess around with your UI due to the big numbers on screen:
	var infinite_stack_capacity_inventory: InventoryManager = __initialize_registry_and_inventory()
	var infinite_stack_capcity_item_registry: ItemRegistry = infinite_stack_capacity_inventory.get_item_registry()
	infinite_stack_capcity_item_registry.set_stack_capacity(item_ids.HEALTH_POTION, 2 ** 63 - 1)
	infinite_stack_capacity_inventory.set_name("InfiniteCapacity")
	var _empty_excess_items: ExcessItems = infinite_stack_capacity_inventory.add(item_ids.HEALTH_POTION, 2 ** 63 - 1)

	# OR:

	# Removing the stack count limit (i.e. the number of stacks or slots an item is allowed to hold)
	# And setting the inventory size to infinite:
	var infinite_inventory: InventoryManager = __initialize_registry_and_inventory()
	infinite_inventory.set_name("InfiniteInventory")
	var no_stack_count_limit_item_registry: ItemRegistry = infinite_inventory.get_item_registry()
	no_stack_count_limit_item_registry.set_stack_count_limit(item_ids.HEALTH_POTION, 0)
	var _ignore_ar: Array[ExcessItems] = infinite_inventory.resize(InventoryManager.INFINITE_SIZE) # internally the memory is not currently allocated and it's only automatically allocated when needed
	var _ignore: Error = infinite_inventory.reserve(10000) # manually allocates memory for 10000 slots (i.e. from slot 0 to slot 9999 will be allocated) but if more memory is needed the manager will add that memory automatically.
	var _ignore_excess_items: ExcessItems = infinite_inventory.add(item_ids.HEALTH_POTION, 99 * 10000) # Performance varies per hardware, but inventory manager should be fast enough for populating 10000 item slots within a frame.


func __initialize_registry_and_inventory() -> InventoryManager:
	var current_path: String = (get_script() as GDScript).get_path().get_base_dir()
	var item_list: Array[Array] = [
		[item_ids.HEALTH_POTION, "Health Potion", "Recovers 5 health.", current_path + "/../inventory_icons/items.atlas_textures/health_potion.tres"],
	]
	var item_registry: ItemRegistry = ItemRegistry.new()
	for item_data: Array in item_list:
		var item_id: int = item_data[0]
		var item_name: String = item_data[1]
		var item_description: String = item_data[2]
		var icon_path: String = item_data[3]
		var icon_texture: Texture2D = load(icon_path)
		item_registry.add_item(item_id, item_name, item_description, icon_texture)
	var inventory_manager: InventoryManager = InventoryManager.new(item_registry)
	return inventory_manager
