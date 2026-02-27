# Demo 6: Item instance data overview
# - Shows registry default instance data vs per-slot overrides.
# - Demonstrates how instance data affects stacking, UI labels, and pricing.
# - Uses comparator-based equality so defaults and overrides are treated consistently.
# - Highlights how null instance data falls back to registry defaults for convenience.
# - Emphasizes that stack compatibility and pricing rules share the same comparator.
extends Control

@export var inventory_item_list_: ItemList
@export var shop_item_list_: ItemList
@export var total_gold_coins_in_inventory_label_: Label
@export var organize_inventory_button_: Button

var item_registry: ItemRegistry = ItemRegistry.new()
var inventory_manager: InventoryManager = null

const inventory_save_file: String = "user://inventory_instance_data.cfg"

enum item_ids {
	DAGGER,
	ENHANCED_DAGGER,
	ENHANCED_STAFF,
	ENHANCED_SWORD,
	GOLD_INGOT,
	HEALTH_POTION,
	MANA_POTION,
	SILVER_INGOT,
	STAFF,
	SWORD,
	GOLD_COIN,
}

## Initializes the demo: registry setup, defaults, inventory load, and UI.
func _ready() -> void:
	randomize()
	# Create a list of item, name, description, icons, and base price.
	# The base price is stored as item metadata in the registry.
	var script: GDScript = get_script()
	var base_icon_path: String = script.get_path().get_base_dir() + "/../inventory_icons/items.atlas_textures/"
	var item_list: Array[Array] = [
		[
			item_ids.HEALTH_POTION,
			"Health Potion",
			"Recovers 5 health.",
			base_icon_path + "health_potion.tres",
			10,
		],
		[
			item_ids.MANA_POTION,
			"Mana Potion",
			"Recovers 5 mana.",
			base_icon_path + "mana_potion.tres",
			20,
		],
		[
			item_ids.SILVER_INGOT,
			"Silver Ingot",
			"Worth 50 gold coins.",
			base_icon_path + "silver_ingot.tres",
			50,
		],
		[
			item_ids.GOLD_INGOT,
			"Gold Ingot",
			"Worth 100 gold coins.",
			base_icon_path + "gold_ingot.tres",
			100,
		],
		[
			item_ids.DAGGER,
			"Dagger",
			"A short sharp knife.",
			base_icon_path + "dagger.tres",
			25,
		],
		[
			item_ids.ENHANCED_DAGGER,
			"Enhanced Dagger",
			"An enhanced short sharp knife.",
			base_icon_path + "enhanced_dagger.tres",
			125,
		],
		[
			item_ids.STAFF,
			"Staff",
			"A magical weapon.",
			base_icon_path + "staff.tres",
			35,
		],
		[
			item_ids.ENHANCED_STAFF,
			"Enhanced Staff",
			"A enhanced magical weapon.",
			base_icon_path + "enhanced_staff.tres",
			135,
		],
		[
			item_ids.SWORD,
			"Sword",
			"A bladed weapon.",
			base_icon_path + "sword.tres",
			40,
		],
		[
			item_ids.ENHANCED_SWORD,
			"Enhanced Sword",
			"A enhanced bladed weapon.",
			base_icon_path + "enhanced_sword.tres",
			140,
		],
	]

	# Initialize the ItemRegistry, which is a small database that contains data about each item in your inventory.
	for item_data: Array in item_list:
		var item_id: int = item_data[0]
		var item_name: String = item_data[1]
		var item_description: String = item_data[2]
		var icon_path: String = item_data[3]
		var icon_texture: Texture2D = load(icon_path)
		var item_price: int = item_data[4]
		item_registry.add_item(item_id, item_name, item_description, icon_texture)
		item_registry.set_item_metadata(item_id, "price", item_price)

	# Register default instance data for a couple of items.
	# These are the fallback values when a slot has no specific instance data.
	# They also drive default labels and baseline pricing in the demo.
	item_registry.set_instance_data(item_ids.SWORD, {"quality": "Common", "durability": 100})
	item_registry.set_instance_data(item_ids.ENHANCED_SWORD, {"quality": "Enhanced", "durability": 120})
	item_registry.set_instance_data(item_ids.STAFF, {"quality": "Common", "durability": 80})
	item_registry.set_instance_data(item_ids.ENHANCED_STAFF, {"quality": "Enhanced", "durability": 100})
	item_registry.set_instance_data(item_ids.DAGGER, {"quality": "Common", "durability": 60})
	item_registry.set_instance_data(item_ids.ENHANCED_DAGGER, {"quality": "Enhanced", "durability": 80})

	# Instance data comparator: only stacks if both "quality" and "durability" match.
	# The same comparator is reused for pricing to keep behavior consistent.
	item_registry.set_instance_data_comparator(item_ids.SWORD, __compare_equipment_instance_data)
	item_registry.set_instance_data_comparator(item_ids.STAFF, __compare_equipment_instance_data)
	item_registry.set_instance_data_comparator(item_ids.DAGGER, __compare_equipment_instance_data)
	item_registry.set_instance_data_comparator(item_ids.ENHANCED_SWORD, __compare_equipment_instance_data)
	item_registry.set_instance_data_comparator(item_ids.ENHANCED_STAFF, __compare_equipment_instance_data)
	item_registry.set_instance_data_comparator(item_ids.ENHANCED_DAGGER, __compare_equipment_instance_data)

	# Include gold coin as the currency
	item_registry.add_item(item_ids.GOLD_COIN, "Gold Coin", "Currency")
	item_registry.set_stack_capacity(item_ids.GOLD_COIN, 999999999)
	item_registry.set_stack_count_limit(item_ids.GOLD_COIN, 1)

	# Create an inventory with the item information just configured
	inventory_manager = InventoryManager.new(item_registry)

	# Load inventory data if any
	if FileAccess.file_exists(inventory_save_file):
		var config_file: ConfigFile = ConfigFile.new()
		var _load_success: int = config_file.load(inventory_save_file)
		var inventory_data: Dictionary = config_file.get_value("Inventory", "data")
		inventory_manager.set_data(inventory_data)
	else:
		# Add some gold coins to the inventory in order to buy/sell items.
		var _ignore_excess: ExcessItems = inventory_manager.add(item_ids.GOLD_COIN, 10000)

	# Refresh inventory
	__refresh_inventory_list()

	## Populate shop item menu
	for item_data: Array in item_list:
		var item_id: int = item_data[0]
		var item_name: String = item_data[1]
		var icon_path: String = item_data[3]
		var icon_texture: Texture2D = load(icon_path)
		var base_price: int = item_registry.get_item_metadata(item_id, "price")
		var index: int = shop_item_list_.add_item(item_name + " (??) - " + str(base_price) + " gold", icon_texture)
		shop_item_list_.set_item_metadata(index, item_id)

	# Connect signals
	var _success: int = shop_item_list_.item_activated.connect(__on_shop_item_list_item_activated)
	_success = inventory_item_list_.item_activated.connect(__on_inventory_item_list_item_activated)
	_success = inventory_manager.slot_modified.connect(__on_inventory_slot_modified)
	_success = organize_inventory_button_.pressed.connect(_on_organize_inventory_button_pressed)


## Orders items into a stable, readable layout.
func _on_organize_inventory_button_pressed() -> void:
	var item_order: PackedInt64Array = [
		item_ids.GOLD_COIN,
		item_ids.HEALTH_POTION,
		item_ids.MANA_POTION,
		item_ids.SILVER_INGOT,
		item_ids.GOLD_INGOT,
		item_ids.DAGGER,
		item_ids.ENHANCED_DAGGER,
		item_ids.STAFF,
		item_ids.ENHANCED_STAFF,
		item_ids.SWORD,
		item_ids.ENHANCED_SWORD,
	]
	inventory_manager.organize(item_order)


func _notification(p_notification: int) -> void:
	if p_notification == Window.NOTIFICATION_WM_CLOSE_REQUEST:
		# Save the inventory:
		var config_file: ConfigFile = ConfigFile.new()
		config_file.set_value("Inventory", "data", inventory_manager.get_data())
		var _success: int = config_file.save(inventory_save_file)


func __on_inventory_slot_modified(_p_slot_number: int) -> void:
	__refresh_inventory_list()


## Handles selling from the inventory; sell price uses instance data rarity.
func __on_inventory_item_list_item_activated(p_item_list_index: int) -> void:
	var slot_number: int = inventory_item_list_.get_item_metadata(p_item_list_index)
	var item_id: int = inventory_manager.get_slot_item_id(slot_number)
	var item_instance_data: Variant = inventory_manager.get_slot_item_instance_data(slot_number)
	# Sell price uses the instance data rarity (default or per-slot override).
	var item_price: int = __get_price_for_item(item_id, item_instance_data)
	var item_name: String = item_registry.get_name(item_id)
	var purchased_amount: int = 1
	var excess_items: ExcessItems = inventory_manager.remove(item_id, 1, item_instance_data)
	if is_instance_valid(excess_items):
		push_warning("Found excess items when removing item. This means inventory manager was not able to remove the item from the inventory. Make sure your code handles this case properly in the UI code.")
	excess_items = inventory_manager.add(item_ids.GOLD_COIN, item_price * purchased_amount)
	if is_instance_valid(excess_items):
		push_warning("Found excess items when adding item. This means inventory manager was not able to add the item to the inventory. Make sure your code handles this case properly in the UI code.")
	var instance_suffix: String = __format_instance_data_suffix(item_id, item_instance_data)
	print("Sold 1 " + item_name + instance_suffix + " for " + str(item_price * purchased_amount) + " gold coins")
	total_gold_coins_in_inventory_label_.set_text("Gold Coins: " + str(inventory_manager.get_item_total(item_ids.GOLD_COIN)))


## Handles buying from the shop; buy price is the static base price.
func __on_shop_item_list_item_activated(p_index: int) -> void:
	var item_id: int = shop_item_list_.get_item_metadata(p_index)
	var item_name: String = item_registry.get_name(item_id)
	var purchased_amount: int = 1
	var instance_data: Variant = __generate_instance_data_for_purchase(item_id)
	# Buy price is the static base price; rarity only affects the sell price.
	var item_price: int = item_registry.get_item_metadata(item_id, "price")
	if inventory_manager.has_item_amount(item_ids.GOLD_COIN, item_price * purchased_amount):
		var _ignore: ExcessItems = inventory_manager.remove(item_ids.GOLD_COIN, item_price * purchased_amount)
		_ignore = inventory_manager.add(item_id, purchased_amount, instance_data)
		var instance_suffix: String = __format_instance_data_suffix(item_id, instance_data)
		print("Purchased 1 " + item_name + instance_suffix + " for " + str(item_price * purchased_amount) + " gold coins")
	else:
		print("Not enough money to buy 1 " + item_name)
	total_gold_coins_in_inventory_label_.set_text("Gold Coins: " + str(inventory_manager.get_item_total(item_ids.GOLD_COIN)))


## Rebuilds the inventory UI list.
## Shows per-slot instance data and whether the value is Default (registry) or Custom.
## Keeps selection stable so the demo feels consistent while items move/merge.
func __refresh_inventory_list() -> void:
	var previously_selected_index: int = -1
	if inventory_item_list_.is_anything_selected():
		var selected_items: PackedInt32Array = inventory_item_list_.get_selected_items()
		previously_selected_index = selected_items[0]
	inventory_item_list_.clear()
	for slot_number: int in inventory_manager.slots():
		if inventory_manager.is_slot_empty(slot_number):
			continue
		var item_id: int = inventory_manager.get_slot_item_id(slot_number)
		if item_id == item_ids.GOLD_COIN:
			continue
		var item_amount: int = inventory_manager.get_slot_item_amount(slot_number)
		var item_name: String = item_registry.get_name(item_id)
		var item_texture: Texture2D = item_registry.get_icon(item_id)
		var item_instance_data: Variant = inventory_manager.get_slot_item_instance_data(slot_number)
		var instance_suffix: String = __format_instance_data_suffix(item_id, item_instance_data)
		var index: int = inventory_item_list_.add_item(item_name + instance_suffix + " - " + str(item_amount), item_texture)
		inventory_item_list_.set_item_metadata(index, slot_number)
	if previously_selected_index != -1:
		inventory_item_list_.force_update_list_size()
		if previously_selected_index < inventory_item_list_.get_item_count():
			inventory_item_list_.select(previously_selected_index)
	total_gold_coins_in_inventory_label_.set_text("Gold Coins: " + str(inventory_manager.get_item_total(item_ids.GOLD_COIN)))


## Generates instance data for equipment; sometimes returns null to use defaults.
func __generate_instance_data_for_purchase(p_item_id: int) -> Variant:
	# Only generate instance data for equipment items.
	if not __is_equipment(p_item_id):
		return null

	# Return null sometimes to use the registry default instance data.
	var use_default_roll: int = randi_range(0, 100)
	if use_default_roll < 25:
		return null

	# Build a per-item instance data dictionary.
	var quality_roll: int = randi_range(0, 100)
	var quality: String = "Common"
	if quality_roll >= 95:
		quality = "Legendary"
	elif quality_roll >= 80:
		quality = "Rare"
	elif quality_roll >= 60:
		quality = "Uncommon"

	var durability: int = randi_range(40, 100)
	return {
		"quality": quality,
		"durability": durability,
	}




## Computes sell price using instance data rarity (via comparator-resolved defaults).
## The comparator is used to decide whether the passed instance data should be treated
## as the registry default for pricing, even if the raw dictionaries differ or are null.
func __get_price_for_item(p_item_id: int, p_instance_data: Variant) -> int:
	var base_price: int = item_registry.get_item_metadata(p_item_id, "price")
	if not __is_equipment(p_item_id):
		return base_price

	var resolved_instance_data: Variant = p_instance_data
	var registered_instance_data: Variant = item_registry.get_instance_data(p_item_id)
	if registered_instance_data != null:
		# Use the registry comparator so pricing treats "default-equivalent" data as default.
		# This keeps pricing consistent with stacking rules and avoids false differences
		# when instance data is null or equivalent to the registry default.
		var comparator: Callable = item_registry.get_instance_data_comparator(p_item_id)
		if p_instance_data == null or comparator.call(registered_instance_data, p_instance_data):
			resolved_instance_data = registered_instance_data

	if not (resolved_instance_data is Dictionary):
		return base_price

	var resolved_instance_data_typed: Dictionary = resolved_instance_data
	var quality: String = resolved_instance_data_typed.get("quality", "Common")
	var multiplier: float = __get_rarity_multiplier(quality)
	return max(1, roundi(base_price * multiplier))

func __get_rarity_multiplier(p_quality: String) -> float:
	match p_quality:
		"Uncommon":
			return 1.2
		"Rare":
			return 1.5
		"Legendary":
			return 2.0
		"Enhanced":
			return 1.3
		_:
			return 1.0

## Formats instance data for display and labels it as Default or Custom.
func __format_instance_data_suffix(p_item_id: int, p_instance_data: Variant) -> String:
	var resolved_instance_data: Variant = p_instance_data
	var registered_instance_data: Variant = item_registry.get_instance_data(p_item_id)
	var is_default: bool = false

	if registered_instance_data != null:
		var comparator: Callable = item_registry.get_instance_data_comparator(p_item_id)
		if p_instance_data == null:
			resolved_instance_data = registered_instance_data
			is_default = true
		elif comparator.call(registered_instance_data, p_instance_data):
			resolved_instance_data = registered_instance_data
			is_default = true

	if resolved_instance_data == null:
		return ""

	var source_label: String = "Custom"
	if is_default:
		source_label = "Default"

	if resolved_instance_data is Dictionary:
		var quality: String = resolved_instance_data.get("quality", "")
		var durability: String = str(resolved_instance_data.get("durability", ""))
		var parts: Array[String] = []
		if not quality.is_empty():
			parts.push_back(quality)
		if not durability.is_empty():
			parts.push_back("Dur " + durability)
		parts.push_back(source_label)
		return " (" + ", ".join(parts) + ")"
	return " (" + str(resolved_instance_data) + ", " + source_label + ")"


## Comparator used by the registry to decide stack compatibility.
## This same comparator is reused for pricing so default-equivalent data is treated
## consistently across stacking, labeling, and gold value.
func __compare_equipment_instance_data(p_first_instance_data: Variant, p_second_instance_data: Variant) -> bool:
	if p_first_instance_data == null and p_second_instance_data == null:
		return true
	if p_first_instance_data == null or p_second_instance_data == null:
		return false
	if not (p_first_instance_data is Dictionary and p_second_instance_data is Dictionary):
		return p_first_instance_data == p_second_instance_data
	return (
		p_first_instance_data.get("quality", null) == p_second_instance_data.get("quality", null)
		and p_first_instance_data.get("durability", null) == p_second_instance_data.get("durability", null)
	)


## Returns true when the item id should use instance data.
func __is_equipment(p_item_id: int) -> bool:
	return (
		p_item_id == item_ids.DAGGER
		or p_item_id == item_ids.ENHANCED_DAGGER
		or p_item_id == item_ids.STAFF
		or p_item_id == item_ids.ENHANCED_STAFF
		or p_item_id == item_ids.SWORD
		or p_item_id == item_ids.ENHANCED_SWORD
	)
