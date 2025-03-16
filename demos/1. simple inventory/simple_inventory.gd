extends Control

# Create
enum item_ids {
	HEALTH_POTION,
}

func _ready() -> void:
	# Create a list of item, name, description, and icons:
	var current_path : String = (get_script() as GDScript).get_path().get_base_dir()
	var item_list : Array[Array] = [
		[item_ids.HEALTH_POTION, "Health Potion", "Recovers 5 health.", current_path + "/../inventory_icons/items.atlas_textures/health_potion.tres"],
	]

	# Initialize the ItemRegistry, which is a small database that contains data about each item in your inventory.
	var item_registry : ItemRegistry = ItemRegistry.new()
	for item_data : Array in item_list:
		var item_id : int =  item_data[0]
		var item_name : String = item_data[1]
		var item_description : String = item_data[2]
		var icon_path : String = item_data[3]
		var icon_texture : Texture2D = load(icon_path)
		item_registry.add_item(item_id, item_name, item_description, icon_texture)

	# Create an inventory with the item information just configured
	var inventory_manager : InventoryManager = InventoryManager.new(item_registry)

	# Add potions to the inventory:
	var _ignore : ExcessItems = inventory_manager.add(item_ids.HEALTH_POTION, 99 + 50)
	# By default the stack capacity is 99 items. The line above added two stacks on the first two item slots: one of 99 potions and another of 50 potions.

	# Print some statistics:
	print("Total Health Potions: ", inventory_manager.get_item_total(item_ids.HEALTH_POTION))
	print("Remaining capacity for Health Potions: ", inventory_manager.get_remaining_capacity_for_item(item_ids.HEALTH_POTION))
