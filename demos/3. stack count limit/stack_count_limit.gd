extends Control

# Create
enum item_ids {
	HEALTH_POTION,
}


func _ready() -> void:
	var inventory_manager: InventoryManager = __initialize_registry_and_inventory()
	var item_registry: ItemRegistry = inventory_manager.get_item_registry()

	# Limit the stack count to just 1
	item_registry.set_stack_count_limit(item_ids.HEALTH_POTION, 1)

	# Add potions to the inventory -- only 99 potions will be added.
	# The rest will be returned as excess items (i.e. items that the add function could not add).
	var excess_items: ExcessItems = inventory_manager.add(item_ids.HEALTH_POTION, 149)

	# Print some statistics:
	print("Excess items: ", excess_items)
	print("Total Health Potions: ", inventory_manager.get_item_total(item_ids.HEALTH_POTION))
	print("Remaining capacity for Health Potions: ", inventory_manager.get_remaining_capacity_for_item(item_ids.HEALTH_POTION))


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
