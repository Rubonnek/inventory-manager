#============================================================================
#  excess_items.gd                                                          |
#============================================================================
#                         This file is part of:                             |
#                            INVENTORY MANAGER                              |
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

class_name ExcessItems
## Represents the amount of items not added to, or not removed from, an inventory.
##
## The item amount is always positive and not clamped.

var _m_item_registry: ItemRegistry = null
var _m_item_id: int = 0
var _m_item_amount: int = 0
var _m_instance_data: Variant = null


## Returns the item ID.
func get_item_id() -> int:
	return _m_item_id


## Sets the item_amount.
func set_amount(p_amount: int) -> void:
	_m_item_amount = p_amount


## Returns the item amount.
func get_amount() -> int:
	return _m_item_amount


## Sets the item instance data.
func set_instance_data(p_instance_data: Variant) -> void:
	_m_instance_data = p_instance_data


## Returns the item instance data that was installed in the inventory. If there wasn't any, the retuning value will fallback to the instance data from the item registry if any. Returns null when none are available.
func get_instance_data() -> Variant:
	if _m_instance_data == null:
		return _m_item_registry.get_instance_data(_m_item_id)
	return _m_instance_data


## Returns the associated [ItemRegistry].
func get_registry() -> ItemRegistry:
	return _m_item_registry


## Returns the item name from its associated [ItemRegistry].
func get_name() -> String:
	return get_registry().get_name(get_item_id())


## Returns the item description from its associated [ItemRegistry].
func get_description() -> String:
	return get_registry().get_description(get_item_id())


## Returns the item icon from its associated [ItemRegistry].
func get_icon() -> Texture2D:
	return get_registry().get_icon(get_item_id())


func _to_string() -> String:
	return "<ExcessItems#%d> Item ID: %d, Name: \"%s\", Amount: %d, Instance Data: %s" % [get_instance_id(), get_item_id(), get_name(), get_amount(), str(get_instance_data())]


func _init(p_item_registry: ItemRegistry, p_item_id: int, p_item_amount: int, p_instance_data: Variant = null) -> void:
	_m_item_registry = p_item_registry
	_m_item_id = p_item_id
	_m_item_amount = p_item_amount
	_m_instance_data = p_instance_data
