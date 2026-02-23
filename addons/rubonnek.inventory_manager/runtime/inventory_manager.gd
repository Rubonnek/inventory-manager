#============================================================================
#  inventory_manager.gd                                                     |
#============================================================================
#                         This file is part of:                             |
#                          INVENTORY MANAGER                                |
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

class_name InventoryManager
## Holds a list of items and their amount.
##
## Holds a list of item IDs and their amount and provides methods for adding, removing, transfering, etc, these items by their slots.

# Design choices:
# * Item slots do not hold any data other than the item ID and their amount. Item name, description, price, etc, are optional.
# * Whenever possible, avoid explicit use of range() to avoid creating an array with all the indices we need to loop over. Avoiding the array creation is way faster for inventories of infinite size. For this reason, under some specific circumstances two loops with the same operations but slightly modified indexes are used.
# * Before extracting data from the item slots array, the indices must be validated and allocated in memory.
# * Instance data is handled this way: whenever there's a getter on the public interface, we search the inventory first for instance data and then the registry for instance data if any. Whenever we are consuming the instance data, the instance data must be normalized (i.e. checked against the item registry and nullified if the instance data is the same as what's installed in the registry).

# Data types for release (compatible with 4.2+)
var _m_inventory_manager_dictionary: Dictionary = {}
var _m_item_slots_packed_array: PackedInt64Array = PackedInt64Array()
var _m_item_stack_count_tracker: Dictionary = {}
var _m_item_slots_tracker: Dictionary = {}
var _m_item_slots_instance_data_tracker: Dictionary = {}
var _m_item_registry: ItemRegistry = null

# Data types for development or performance (compatible with 4.4+)
# var _m_inventory_manager_dictionary: Dictionary = {}
# var _m_item_slots_packed_array: PackedInt64Array = PackedInt64Array()
# var _m_item_stack_count_tracker: Dictionary[int, int] = {}
# var _m_item_slots_tracker: Dictionary[int, PackedInt64Array] = {}
# var _m_item_slots_instance_data_tracker: Dictionary[int, Variant] = {}
# var _m_item_registry: ItemRegistry = null

## Emitted when an item fills an empty slot.
signal item_added(p_slot_index: int, p_item_id: int)

## Emitted when an item slot is modified.
signal slot_modified(p_slot_index: int)

## Emitted when a slot is emptied and the item is removed.
signal item_removed(p_slot_index: int, p_item_id: int)

## Emitted when the inventory is cleared.
signal inventory_cleared()

enum _key {
	ITEM_SLOTS,
	INSTANCE_DATA_TRACKER,
	SIZE,
}

const _DEFAULT_SIZE: int = 200
const INFINITE_SIZE: int = -1
const _INT64_MAX: int = 2 ** 63 - 1


## Adds the specified item amount to the inventory.[br]
## When [code]p_start_slot_number[/code] is specified and it is possible to create more stacks for the specified item, the manager will attempt to add items at the specified slot or at any higher slot if needed, also looping around to the beginning of the inventory when necessary as well.[br][br]
## When [code]p_partial_add[/code] is true (default), if the amount exceeds what can be added to the inventory and there is still some capacity for the item, the remaining item amount not added to the inventory will be returned as an [ExcessItems].[br][br]
## When [code]p_partial_add[/code] is false, if the amount exceeds what can be added to the inventory, the item amount will not be added at all to the inventory and will be returned as an [ExcessItems].
func add(p_item_id: int, p_amount: int, p_instance_data: Variant = null, p_start_slot_number: int = -1, p_partial_add: bool = true) -> ExcessItems:
	if p_item_id < 0:
		push_warning("InventoryManager: Attempted to add an item with invalid item ID (%d). Ignoring call. The item ID must be equal or greater than zero." % p_item_id)
		return null
	if p_amount == 0:
		return null
	if p_amount < 0:
		push_warning("InventoryManager: Attempted to add an item with negative amount. Ignoring call. The amount must be positive.")
		return null
	var inventory_size: int = size()
	if p_start_slot_number != -1 and not is_slot_valid(p_start_slot_number):
		push_warning("InventoryManager: Attempted to add item ID (%d) with an invalid start index (%d). Forcing start index to -1." % [p_item_id, p_start_slot_number])
		p_start_slot_number = -1

	# Make sure to always fallback instance data to whatever is on the registry:
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)

	if not p_partial_add:
		if p_amount > get_remaining_capacity_for_item(p_item_id, normalized_instance_data):
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)

	# Grab item id data
	var registered_stack_count: int = _m_item_registry.get_stack_count(p_item_id)
	var current_stack_count: int = _m_item_stack_count_tracker.get(p_item_id, 0)
	var is_stack_count_limited: bool = _m_item_registry.is_stack_count_limited(p_item_id)

	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)

	if p_start_slot_number < 0:
		# Then a start index was not passed.
		# First fill all the slots with available stack space while skipping empty slots
		var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
		for slot_number: int in item_id_slots_array:
			var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
			if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
				continue
			p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
			if p_amount == 0:
				return null

		# We still have some more item amount to add. We'll need to create the item slots for these.
		# Check if the stack count is limited -- let's make sure we don't go over the number of registered stack count.
		if is_stack_count_limited and current_stack_count >= registered_stack_count:
			# We've stumbled upon the maximum number of stacks and added items to all of them. No more items can be added.
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)

		if is_infinite():
			# Add items to empty slots either until we hit the stack count limit or the amount of items remainind to add reaches 0.
			var slot_number: int = 0
			while true:
				# Increase the inventory size if needed
				if not __is_slot_allocated(slot_number):
					__increase_size(slot_number)

				if __is_slot_empty(slot_number):
					# Add item:
					p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
					if p_amount == 0:
						# We are done adding items. There's no excess.
						return null

					# Update the stack count
					current_stack_count += 1
					if is_stack_count_limited and current_stack_count >= registered_stack_count:
						# We can't add any more of this item. Return the excess items.
						return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
				slot_number += 1
				if slot_number < 0:
					push_warning("InventoryManager: Detected integer overflow in add(). Exiting loop.")
					return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
		else: # Inventory size is limited.
			# Add items to empty slots either until we hit the stack count limit or the amount of items remaining to add reaches 0.
			for slot_number: int in inventory_size:
				# Increase the inventory size if needed
				if not __is_slot_allocated(slot_number):
					__increase_size(slot_number)

				if __is_slot_empty(slot_number):
					# Add item:
					p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)

					if p_amount == 0:
						# We are done adding items. There's no excess.
						return null

					# Check if we've reached to all the stacks we can add:
					current_stack_count += 1
					if is_stack_count_limited and current_stack_count >= registered_stack_count:
						# Couldn't add all the items to the inventory. Return the excess items.
						return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
	else:
		# If the current stack capacity is greater or equal to the registered size, no more stacks can be added.
		if is_stack_count_limited and current_stack_count >= registered_stack_count:
			# No more stacks can be added. We can only add items to the current stacks
			# Let's do so:
			var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
			for slot_number: int in item_id_slots_array:
				var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
				if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
					continue
				p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					return null
			# Couldn't add all the items to the inventory. Return the excess items.
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)

		# We can add more stacks to the inventory. Let's do so.
		if is_infinite():
			var slot_number: int = p_start_slot_number
			while true:
				# Increase the inventory size if needed
				if not __is_slot_allocated(slot_number):
					__increase_size(slot_number)

				if __is_slot_empty(slot_number) and (not is_stack_count_limited or current_stack_count < registered_stack_count):
					p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
					current_stack_count += 1
				elif __get_slot_item_id(slot_number) == p_item_id:
					var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
					if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
						# NOTE: We don't count this stack since it already has been accounted for
						p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					# There's nothing else to add.
					return null
				slot_number += 1
				if slot_number < 0:
					push_warning("InventoryManager: Detected integer overflow. Exiting loop.")
					break
				if is_stack_count_limited and current_stack_count >= registered_stack_count:
					# Cannot add any more items.
					break

			# It may be possible to add some more items. Go over all the current stacks and attempt to add more items:
			var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
			for slot_number_loop_around: int in item_id_slots_array:
				var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number_loop_around, null)
				if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
					continue
				p_amount = __add_items_to_slot(slot_number_loop_around, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					return null
			# Couldn't add all the items to the inventory. Return the excess items.
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
		else: # the inventory size is limited, but it's possible we can add more stacks
			for slot_number: int in inventory_size - p_start_slot_number:
				if is_stack_count_limited and current_stack_count >= registered_stack_count:
					# Cannot add any more items. We may need to either loop around the remaining items or return the excess items.
					break
				# Increase the inventory size if needed
				if not __is_slot_allocated(slot_number + p_start_slot_number):
					__increase_size(slot_number + p_start_slot_number)
				if __is_slot_empty(slot_number + p_start_slot_number) and (not is_stack_count_limited or current_stack_count < registered_stack_count):
					p_amount = __add_items_to_slot(slot_number + p_start_slot_number, p_item_id, p_amount, normalized_instance_data)
					current_stack_count += 1
				elif __get_slot_item_id(slot_number + p_start_slot_number) == p_item_id:
					var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number + p_start_slot_number, null)
					if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
						# NOTE: We don't count this stack since it already has been accounted for
						p_amount = __add_items_to_slot(slot_number + p_start_slot_number, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					# There's nothing else to add.
					return null
				if is_stack_count_limited and current_stack_count >= registered_stack_count:
					# Couldn't add all the items to the inventory. There are still more items to add.
					break
			if p_start_slot_number != 0:
				# Loop around the remaining slots.
				for slot_number: int in p_start_slot_number:
					if __is_slot_empty(slot_number) and (not is_stack_count_limited or current_stack_count < registered_stack_count):
						current_stack_count += 1
						p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
					elif __get_slot_item_id(slot_number) == p_item_id:
						var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
						if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
							p_amount = __add_items_to_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
					if p_amount == 0:
						# There's nothing else to add.
						return null
				# We've looped through the remaining slots and not all items could be added. Return the excess items.
				return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
	# Could not add some items to the inventory. Return those.
	return __create_excess_items(p_item_id, p_amount, normalized_instance_data)


## Removes the specified item amount to the inventory.[br]
## When [code]p_start_slot_number[/code] is specified,  the manager will attempt to remove items from the specified slot or at any higher slot if needed, also looping around to the beginning of the inventory when necessary as well.[br][br]
## When [code]p_partial_removal[/code] is true (default), if the amount exceeds what can be removed from the inventory and there are still some items in the inventory, the remaining item amount within the inventory will be removed and the non-removed items will be returned as an [ExcessItems].[br][br]
## When [code]p_partial_removal[/code] is false, if the amount exceeds what can be removed from the inventory, the item amount will not be removed at all from the inventory and instead will be returned as an [ExcessItems].
func remove(p_item_id: int, p_amount: int, p_instance_data: Variant = null, p_start_slot_number: int = -1, p_partial_removal: bool = true) -> ExcessItems:
	if not _m_item_registry.has_item(p_item_id):
		push_warning("InventoryManager: Removing unregistered item with id (%d) from the inventory. The default stack capacity and max stacks values will be used. Register item ID within the item registry before removing item from the inventory to silence this message." % p_item_id)
	if p_amount == 0:
		return null
	if p_amount < 0:
		push_warning("InventoryManager: Attempted to remove item ID (%d) with a negative amount (%d). Ignoring call." % [p_item_id, p_amount])
		return null
	if p_start_slot_number != -1 and not is_slot_valid(p_start_slot_number):
		push_warning("InventoryManager: Attempted to remove item ID (%d) with an invalid start index (%d). Item removal will happen from the start of the inventory." % [p_item_id, p_start_slot_number])
		p_start_slot_number = -1

	# Make sure to always fallback instance data to whatever is on the registry:
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)

	if not p_partial_removal:
		if p_amount > get_item_total(p_item_id, normalized_instance_data):
			return __create_excess_items(p_item_id, p_amount, normalized_instance_data)

	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)

	if p_start_slot_number < 0:
		# A start index was not given. We can start removing items from all the slots.
		for slot_number: int in __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size()):
			if __is_slot_empty(slot_number):
				# Nothing to remove here
				continue
			if __get_slot_item_id(slot_number) == p_item_id:
				var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
				if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
					continue
				p_amount = __remove_items_from_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					# We are done removing items. There's nothing more to remove.
					return null
		return __create_excess_items(p_item_id, p_amount, normalized_instance_data)
	else:
		# A start index was given. We can start removing items from the slots, starting from there.
		var total_slots: int = __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())
		for offseted_slot_number: int in total_slots - p_start_slot_number:
			var slot_number: int = offseted_slot_number + p_start_slot_number
			if __is_slot_empty(slot_number):
				# Nothing to remove here
				continue
			if __get_slot_item_id(slot_number) == p_item_id:
				var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
				if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
					continue
				p_amount = __remove_items_from_slot(slot_number, p_item_id, p_amount, normalized_instance_data)
			if p_amount == 0:
				# There's nothing else to remove.
				return null
		if p_start_slot_number != 0:
			# Loop around the remaining slots -- cap at the number of allocated slots to avoid out-of-bounds access. The start slot number may be valid but the slot may not be allocated.
			for slot_number_loop_around: int in mini(p_start_slot_number, total_slots):
				if __is_slot_empty(slot_number_loop_around):
					# Nothing to remove here
					continue
				if __get_slot_item_id(slot_number_loop_around) == p_item_id:
					var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number_loop_around, null)
					if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
						continue
					p_amount = __remove_items_from_slot(slot_number_loop_around, p_item_id, p_amount, normalized_instance_data)
				if p_amount == 0:
					# There's nothing else to remove.
					return null
		return __create_excess_items(p_item_id, p_amount, normalized_instance_data)


## Adds items to the specified slot number. Returns the number of items not added to the slot.
func add_items_to_slot(p_slot_index: int, p_item_id: int, p_amount: int, p_instance_data: Variant = null) -> int:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Attempted to add an item to invalid slot '%d'. Ignoring call." % [p_slot_index])
		return p_amount
	if not __is_slot_allocated(p_slot_index):
		__increase_size(p_slot_index)
	if p_amount < 0:
		push_warning("InventoryManager: add amount must be positive. Ignoring.")
		return p_amount
	elif p_amount == 0:
		# There's nothing to do.
		return p_amount

	# Make sure to always fallback instance data to whatever is on the registry:
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)

	var was_slot_empty: int = __is_slot_empty(p_slot_index)
	if not was_slot_empty:
		var slot_item_id: int = __get_slot_item_id(p_slot_index)
		if p_item_id != slot_item_id:
			push_warning("InventoryManager: attempted to add an item to slot '%d' with ID '%d'. Expected ID '%d'. Ignoring call." % [p_slot_index, p_item_id, slot_item_id])
			return p_amount

		# Compare instance data -- we can't add the item to the slot if the slot is not empty and the normalized instance data differs.
		var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_slot_index, null)
		var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
		if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
			push_warning("InventoryManager: Attempted to add an item to slot '%d' with different instance data than what is already in the slot. Ignoring call." % p_slot_index)
			return p_amount

	# Processed the item addition to the slot
	return __add_items_to_slot(p_slot_index, p_item_id, p_amount, normalized_instance_data)


## Removes items from the specified slot number. Returns the number of items not removed from the slot.
func remove_items_from_slot(p_slot_index: int, p_item_id: int, p_amount: int, p_instance_data: Variant = null) -> int:
	if p_item_id < 0:
		push_warning("InventoryManager: attempted to remove an invalid item ID '%d'. Ignoring." % p_item_id)
		return p_amount
	if p_amount < 0:
		push_warning("InventoryManager: remove amount must be positive. Ignoring.")
		return p_amount
	elif p_amount == 0:
		# There's nothing to do.
		return p_amount
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: attempted to remove items on an invalid slot number '%d'. Ignoring." % p_slot_index)
		return p_amount
	if not __is_slot_allocated(p_slot_index) or __is_slot_empty(p_slot_index):
		# Slot is valid yet not allocated or empty. There's nothing to remove in either case.
		return p_amount
	var item_id: int = __get_slot_item_id(p_slot_index)
	if item_id != p_item_id:
		push_warning("InventoryManager: attempted to remove an item with ID '%d' from slot '%d' which has a different associated item id '%d'. Ignoring call." % [p_item_id, p_slot_index, item_id])
		return p_amount

	# Make sure to always fallback instance data to whatever is on the registry:
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)

	# Compare instance data -- we can't remove the item from the slot if the slot's instance data differs.
	var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_slot_index, null)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
		push_warning("InventoryManager: Attempted to remove an item from slot '%d' with different instance data than what is in the slot. Ignoring call." % p_slot_index)
		return p_amount
	return __remove_items_from_slot(p_slot_index, p_item_id, p_amount, normalized_instance_data)


## Swaps the items from the specified slots.
func swap(p_first_slot_number: int, p_second_slot_number: int) -> void:
	if not is_slot_valid(p_first_slot_number):
		push_warning("InventoryManager: Attempted to swap an item to invalid slot '%d'. Ignoring call." % [p_first_slot_number])
		return
	if not is_slot_valid(p_second_slot_number):
		push_warning("InventoryManager: Attempted to swap an item to invalid slot '%d'. Ignoring call." % [p_second_slot_number])
		return

	# Increase inventory size if needed
	var max_slot_number: int = maxi(p_first_slot_number, p_second_slot_number)
	if not __is_slot_allocated(max_slot_number):
		__increase_size(max_slot_number)

	if is_slot_empty(p_first_slot_number) and is_slot_empty(p_second_slot_number):
		# There's nothing to do
		return

	elif not is_slot_empty(p_first_slot_number) and is_slot_empty(p_second_slot_number):
		# Get data
		var first_slot_item_id: int = __get_slot_item_id(p_first_slot_number)
		var first_slot_item_amount: int = __get_slot_item_amount(p_first_slot_number)

		# Calculate target indexes
		var second_slot_item_id_index: int = __calculate_slot_item_id_index(p_second_slot_number)
		var second_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_second_slot_number)

		# Inject data
		_m_item_slots_packed_array[second_slot_item_id_index] = first_slot_item_id
		_m_item_slots_packed_array[second_slot_item_amount_index] = first_slot_item_amount

		# Update item id slot tracker
		__remove_item_id_slot_from_tracker(first_slot_item_id, p_first_slot_number)
		__add_item_id_slot_to_tracker(first_slot_item_id, p_second_slot_number)

		# Update item instance data tracker
		var first_slot_item_instance: Variant = _m_item_slots_instance_data_tracker.get(p_first_slot_number, null)
		if first_slot_item_instance != null:
			_m_item_slots_instance_data_tracker[p_second_slot_number] = first_slot_item_instance
			var _success: bool = _m_item_slots_instance_data_tracker.erase(p_first_slot_number)

		# Clear
		var first_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_first_slot_number)
		_m_item_slots_packed_array[first_slot_item_amount_index] = 0
	elif is_slot_empty(p_first_slot_number) and not is_slot_empty(p_second_slot_number):
		# Get data
		var second_slot_item_id: int = __get_slot_item_id(p_second_slot_number)
		var second_slot_item_amount: int = __get_slot_item_amount(p_second_slot_number)

		# Calculate target indexes
		var first_slot_item_id_index: int = __calculate_slot_item_id_index(p_first_slot_number)
		var first_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_first_slot_number)

		# Inject data
		_m_item_slots_packed_array[first_slot_item_id_index] = second_slot_item_id
		_m_item_slots_packed_array[first_slot_item_amount_index] = second_slot_item_amount

		# Update item id slot tracker
		__remove_item_id_slot_from_tracker(second_slot_item_id, p_second_slot_number)
		__add_item_id_slot_to_tracker(second_slot_item_id, p_first_slot_number)

		# Update item instance data tracker
		var second_slot_item_instance: Variant = _m_item_slots_instance_data_tracker.get(p_second_slot_number, null)
		if second_slot_item_instance != null:
			_m_item_slots_instance_data_tracker[p_first_slot_number] = second_slot_item_instance
			var _success: bool = _m_item_slots_instance_data_tracker.erase(p_second_slot_number)

		# Clear
		var second_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_second_slot_number)
		_m_item_slots_packed_array[second_slot_item_amount_index] = 0
	elif not is_slot_empty(p_second_slot_number) and not is_slot_empty(p_first_slot_number):
		# Get data
		var first_slot_item_id: int = __get_slot_item_id(p_first_slot_number)
		var first_slot_item_amount: int = __get_slot_item_amount(p_first_slot_number)
		var second_slot_item_id: int = __get_slot_item_id(p_second_slot_number)
		var second_slot_item_amount: int = __get_slot_item_amount(p_second_slot_number)

		# Calculate target indexes
		var first_slot_item_id_index: int = __calculate_slot_item_id_index(p_first_slot_number)
		var first_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_first_slot_number)
		var second_slot_item_id_index: int = __calculate_slot_item_id_index(p_second_slot_number)
		var second_slot_item_amount_index: int = __calculate_slot_item_amount_index(p_second_slot_number)

		# Inject data
		_m_item_slots_packed_array[first_slot_item_id_index] = second_slot_item_id
		_m_item_slots_packed_array[first_slot_item_amount_index] = second_slot_item_amount
		_m_item_slots_packed_array[second_slot_item_id_index] = first_slot_item_id
		_m_item_slots_packed_array[second_slot_item_amount_index] = first_slot_item_amount

		# Update item id slot tracker
		__remove_item_id_slot_from_tracker(first_slot_item_id, p_first_slot_number)
		__add_item_id_slot_to_tracker(first_slot_item_id, p_second_slot_number)
		__remove_item_id_slot_from_tracker(second_slot_item_id, p_second_slot_number)
		__add_item_id_slot_to_tracker(second_slot_item_id, p_first_slot_number)

		# Update item instance data tracker
		var first_slot_item_instance: Variant = _m_item_slots_instance_data_tracker.get(p_first_slot_number, null)
		var second_slot_item_instance: Variant = _m_item_slots_instance_data_tracker.get(p_second_slot_number, null)
		if first_slot_item_instance != null:
			_m_item_slots_instance_data_tracker[p_second_slot_number] = first_slot_item_instance
		else:
			var _success: bool = _m_item_slots_instance_data_tracker.erase(p_second_slot_number)
		if second_slot_item_instance != null:
			_m_item_slots_instance_data_tracker[p_first_slot_number] = second_slot_item_instance
		else:
			var _success: bool = _m_item_slots_instance_data_tracker.erase(p_first_slot_number)

	slot_modified.emit(p_first_slot_number)
	slot_modified.emit(p_second_slot_number)

	# Sync change with the debugger:
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			EngineDebugger.send_message("inventory_manager:swap", [get_instance_id(), p_first_slot_number, p_second_slot_number])

## Returns true when a transfer is possible. Returns false when otherwise.
## NOTE: Assumes slot numbers are valid and the safety checks have passed already
#func __can_transfer(p_first_slot_number: int, p_first_amount: int, p_second_slot_number: int) -> bool:
#	return true

## Transfers items from first specified slot to the second specified slot. Transfers are only possible if both slots have the same item ID and the same instance data or the second slot is empty. Use [method can_transfer] to check this.
func transfer(p_first_slot_number: int, p_first_amount: int, p_second_slot_number: int) -> ExcessItems:
	if not is_slot_valid(p_first_slot_number):
		push_warning("InventoryManager: Attempted to transfer an item from invalid slot '%d'. Ignoring call." % [p_first_slot_number])
		return null
	if not is_slot_valid(p_second_slot_number):
		push_warning("InventoryManager: Attempted to transfer an item to invalid slot '%d'. Ignoring call." % [p_second_slot_number])
		return null
	if p_first_amount < 0:
		push_warning("InventoryManager: Attempted to transfer an item from slot '%d' with invalid slot with negative amount '%d'. Ignoring call." % [p_first_slot_number, p_first_amount])
		return null
	if __is_slot_empty(p_first_slot_number):
		# There's nothing to do
		return null
	# Increase inventory size if needed -- the operations below require this
	var max_slot_number: int = maxi(p_first_slot_number, p_second_slot_number)
	if not __is_slot_allocated(max_slot_number):
		__increase_size(max_slot_number)

	# Get IDs
	var first_item_id: int = __get_slot_item_id(p_first_slot_number)
	var second_item_id: int = __get_slot_item_id(p_second_slot_number)

	# Check if it's possible to transfer:
	var is_second_slot_empty: bool = __is_slot_empty(p_second_slot_number)
	if first_item_id == second_item_id or is_second_slot_empty:
		# Grab the first item instance data. We'll need this.
		var first_item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_first_slot_number, null)

		# If the second slot is not empty, we need to check if both instance datas are equal
		if not is_second_slot_empty:
			# We need to check if both slots instance data is equal because otherwise we can't make the transfer since the slots are not really compatible
			var second_item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_second_slot_number, null)
			var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(first_item_id)
			if not registered_instance_data_comparator.call(first_item_instance_data, second_item_instance_data):
				return __create_excess_items(first_item_id, p_first_amount, first_item_instance_data)

		# Then it's possible to transfer. Do a sanity check on the amounts.
		var first_slot_item_amount: int = __get_slot_item_amount(p_first_slot_number)
		var target_amount: int = clampi(p_first_amount, 0, first_slot_item_amount)

		# Is this a total transfer?
		if target_amount != first_slot_item_amount:
			# This is not a total transfer of the item from one slot to another.

			# Check if we are adding a new stack during the partial transfer
			var are_we_creating_a_new_stack: int = 0
			if is_second_slot_empty:
				# We are creating a new stack
				are_we_creating_a_new_stack = 1

			# Check if we go over the stack count limit on this transfer operation.
			var current_stack_count: int = _m_item_stack_count_tracker[first_item_id]
			var registered_stack_count: int = _m_item_registry.get_stack_count(first_item_id)
			var is_stack_count_limited: bool = _m_item_registry.is_stack_count_limited(first_item_id)
			if is_stack_count_limited and current_stack_count + are_we_creating_a_new_stack > registered_stack_count:
				push_warning("InventoryManager: Attempted partial item amount transfer on item id (%d) from slot '%d' to slot '%d' but this transfer violates the item's maximum stack count (%d). After the transfer the stack count would have been %d. Ignoring call." % [first_item_id, p_first_slot_number, p_second_slot_number, registered_stack_count, current_stack_count + are_we_creating_a_new_stack])
				return null

			# We don't go over the stack count limit. Perform the transfer.

			# Let's remove the items from the first slot.
			var remainder: int = __remove_items_from_slot(p_first_slot_number, first_item_id, target_amount, first_item_instance_data)
			assert(remainder == 0, "InventoryManager: removal from partial transfer yielded a non zero remainder. This should not happen at all.")

			# Add items to the second slot
			remainder = __add_items_to_slot(p_second_slot_number, first_item_id, target_amount, first_item_instance_data)

			# Is there a remainder?
			if remainder != 0:
				# There is. We've hit the maximum stack capacity on the second slot.

				# We've already checked that we don't go over the stack count limit.

				# Add the items to the first slot.
				remainder = __add_items_to_slot(p_first_slot_number, first_item_id, remainder, first_item_instance_data)
				if remainder != 0:
					push_warning("InventoryManager: Attempted partial item amount transfer on item id (%d) from slot '%d' to slot '%d' Resulted in excess items after completing the operation. The item amounts found in the inventory seem to be higher than allowed by the item registry. You may want to run organize() to fix this possible on the remaining slots." % [first_item_id, p_first_slot_number, p_second_slot_number])
					return __create_excess_items(first_item_id, remainder, first_item_instance_data)

			# The transfer operation completed successfully
			return null
		else:
			# This is a total transfer attempt. No need to check if we are creating a new stack for now.

			# Let's remove all the items from the first slot.
			var remainder: int = __remove_items_from_slot(p_first_slot_number, first_item_id, target_amount, first_item_instance_data)
			assert(remainder == 0, "InventoryManager: removal from total transfer yielded a non zero remainder. This should not happen at all.")

			# Add items to the second slot
			remainder = __add_items_to_slot(p_second_slot_number, first_item_id, target_amount, first_item_instance_data)

			# Is there a remainder?
			if remainder != 0:
				# There is. We've hit the maximum stack capacity on the second slot.

				# Check if we go over the stack count limit on the remainder of this transfer operation.
				var current_stack_count: int = _m_item_stack_count_tracker[first_item_id]
				var registered_stack_count: int = _m_item_registry.get_stack_count(first_item_id)
				var is_stack_count_limited: bool = _m_item_registry.is_stack_count_limited(first_item_id)
				if is_stack_count_limited and current_stack_count + 1 > registered_stack_count:
					push_warning("InventoryManager: Attempted partial item amount transfer on item id (%d) from slot '%d' to slot '%d' but this transfer violates the item's maximum stack count (%d). After the transfer the stack count would have been %d. Returning excess items." % [first_item_id, p_first_slot_number, p_second_slot_number, registered_stack_count, current_stack_count + 1])
					return __create_excess_items(first_item_id, remainder, first_item_instance_data)

				# We don't go over the stack count limit. Add the items to the slot.
				remainder = __add_items_to_slot(p_first_slot_number, first_item_id, remainder, first_item_instance_data)
				if remainder != 0:
					push_warning("InventoryManager: Attempted partial item amount transfer on item id (%d) from slot '%d' to slot '%d' Resulted in excess items after completing the operation. The item amounts found in the inventory seem to be higher than allowed by the item registry. You may want to run organize() to fix this possible on the remaining slots." % [first_item_id, p_first_slot_number, p_second_slot_number])
					return __create_excess_items(first_item_id, remainder, first_item_instance_data)

			# The transfer operation completed successfully
			return null
	else:
		push_warning("InventoryManager: Attempted to transfer an item id (%d) from slot '%d' to slot '%d' with mismatching IDs. Ignoring call." % [first_item_id, p_first_slot_number, p_second_slot_number])
		return null


## Reserves memory up to the desired number of slots in memory as long as the inventory size allows. Returns OK when successful.
func reserve(p_number_of_slots: int = -1) -> Error:
	var allocated_slots: int = __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())
	if p_number_of_slots <= allocated_slots:
		return OK
	var max_size_limit: int = 0
	var inventory_size: int = size()
	if is_infinite():
		max_size_limit = _INT64_MAX
	else:
		max_size_limit = inventory_size
	p_number_of_slots = clampi(p_number_of_slots, 0, max_size_limit)
	var max_slot_index: int = p_number_of_slots - 1
	var array_size: int = __calculate_array_size_needed_to_access_slot_index(max_slot_index)
	var error: int = _m_item_slots_packed_array.resize(array_size)
	if error != OK:
		push_warning("InventoryManager: could not properly preallocate the array")
		return error as Error
	return OK


## Returns the item ID for the given item slot. Returns -1 on invalid or empty slots.
func get_slot_item_id(p_slot_index: int) -> int:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to get_slot_item_id()." % p_slot_index)
		return -1
	if not __is_slot_allocated(p_slot_index):
		return -1
	if __is_slot_empty(p_slot_index):
		return -1
	var item_id: int = __get_slot_item_id(p_slot_index)
	return item_id


## Returns the item amount for the given item slot. Returns 0 on empty or invalid slots.
func get_slot_item_amount(p_slot_index: int) -> int:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to get_slot_item_amount()." % p_slot_index)
		return 0
	if not __is_slot_allocated(p_slot_index):
		return 0
	var amount: int = __get_slot_item_amount(p_slot_index)
	return amount


## Returns the slot item instance data. Returns null if there's no associated instance data.
## Note: there are two levels of item instance data. The instance data registered within the ItemRegistry and the slot-specific item instance data. If there is no slot specific instance data, this function returns the instance data registered at the item registry if there's any.
func get_slot_item_instance_data(p_slot_index: int) -> Variant:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to get_slot_item_instance_data()." % p_slot_index)
		return null
	if not __is_slot_allocated(p_slot_index):
		return null
	if is_slot_empty(p_slot_index):
		return null
	var item_id: int = __get_slot_item_id(p_slot_index)
	var item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_slot_index, null)
	if item_instance_data == null:
		item_instance_data = _m_item_registry.get_instance_data(item_id)
	return item_instance_data


## Returns the item instance data comparator for the item id at the specified slot. Returns an invalid [Callable] when the slot is empty or invalid.
func get_slot_item_instance_data_comparator(p_slot_index: int) -> Callable:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to get_slot_item_instance_data_comparator()." % p_slot_index)
		return Callable()
	if not __is_slot_allocated(p_slot_index):
		return Callable()
	if is_slot_empty(p_slot_index):
		return Callable()
	var item_id: int = __get_slot_item_id(p_slot_index)
	var item_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(item_id)
	return item_instance_data_comparator


## Sets the slot item instance data
func set_slot_item_instance_data(p_slot_index: int, p_item_instance_data: Variant) -> void:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to set_slot_item_instance_data()." % p_slot_index)
		return
	if is_slot_empty(p_slot_index):
		push_warning("InventoryManager: Attempted to set item instance data on slot (%d) which is empty. Ignoring" % p_slot_index)
		return
	__set_slot_item_instance_data(p_slot_index, p_item_instance_data)


## Returns true when the item slot is is empty. Returns false otherwise. Checking if the slot is empty does not mean it is valid or reachable if the inventory is strictly sized.
func is_slot_empty(p_slot_index: int) -> bool:
	if not is_slot_valid(p_slot_index):
		push_warning("InventoryManager: Invalid slot (%d) passed to is_slot_empty()." % p_slot_index)
		return false
	if not __is_slot_allocated(p_slot_index):
		return true
	var slot_item_amount: int = __get_slot_item_amount(p_slot_index)
	return slot_item_amount <= 0


## Returns true if the slot index is valid.
func is_slot_valid(p_slot_index: int) -> bool:
	if p_slot_index < 0:
		return false
	var inventory_size: int = size()
	if is_infinite():
		return true
	return p_slot_index < inventory_size


## Returns the remaining amount of items the specified slot can hold. Returns -1 on an invalid slot or if the specified item id or instance data mismatches the one found in the slot. On empty slots returns the stack capacity as registered in the item registry.
func get_remaining_slot_capacity(p_slot_index: int, p_item_id: int, p_instance_data: Variant = null) -> int:
	if not is_slot_valid(p_slot_index):
		return -1
	if not __is_slot_allocated(p_slot_index) or __is_slot_empty(p_slot_index):
		# The slot is not allocated, but empty:
		return _m_item_registry.get_stack_capacity(p_item_id)
	# The slot is allocated and not empty.
	var item_id: int = __get_slot_item_id(p_slot_index)
	if item_id != p_item_id:
		push_warning("InventoryManager: Mismatching item id found when attempting to get remaining slot capacity at slot '%d'." % p_slot_index)
		return -1
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(p_slot_index, null)
	if not registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
		push_warning("InventoryManager: Mismatching item instance data found when attempting to get remaining slot capacity at slot '%d'." % p_slot_index)
		return -1
	return __get_remaining_slot_capacity(p_slot_index, p_item_id)


## Returns true when the inventory is empty. Returns false otherwise.
func is_empty() -> bool:
	return _m_item_stack_count_tracker.is_empty()


## Returns the total sum of the specified item across all stacks within the inventory.[br]
func get_item_total(p_item_id: int, p_instance_data: Variant = null) -> int:
	var item_count: int = 0
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	for slot_number: int in item_id_slots_array:
		var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
		if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
			item_count += __get_slot_item_amount(slot_number)
	return item_count


## Returns true if the inventory holds at least the specified amount of the item in question.[br]
## When [code]p_instance_data[/code] is null (default), the check is performed across all instance data variations.[br]
## When [code]p_instance_data[/code] is not null, only the stacks with matching instance data are considered.
func has_item_amount(p_item_id: int, p_amount: int, p_instance_data: Variant = null) -> bool:
	var item_count: int = 0
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	for slot_number: int in item_id_slots_array:
		var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
		if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
			item_count += __get_slot_item_amount(slot_number)
			if item_count >= p_amount:
				return true
	return item_count >= p_amount


## Returns true when one item with the specified item ID is found within the inventory. Returns false otherwise.[br]
## When [code]p_instance_data[/code] is null (default), returns true if any stack of the item exists regardless of instance data.[br]
## When [code]p_instance_data[/code] is not null, returns true only if a stack with matching instance data exists.
func has_item(p_item_id: int, p_instance_data: Variant = null) -> bool:
	if p_instance_data == null:
		return p_item_id in _m_item_slots_tracker
	# Non-null instance data was provided -- check for at least one matching slot
	var normalized_instance_data: Variant = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
	for slot_number: int in item_id_slots_array:
		var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
		if registered_instance_data_comparator.call(normalized_instance_data, slot_instance_data):
			return true
	return false


## Changes the inventory size and returns an array of excess items after the specified slot number if any are found.[br][br]
## When the size is set to [code]InventoryManager.INFINITE_SIZE[/code], the inventory size is not increased in memory but increased upon demand. If slot preallocation is required for its performance benefit, use [method reserve].
func resize(p_new_slot_count: int) -> Array[ExcessItems]:
	var excess_items_array: Array[ExcessItems] = []
	if p_new_slot_count != INFINITE_SIZE and p_new_slot_count < 0:
		push_warning("InventoryManager: Invalid new inventory size detected (%d). The new size should be greater or equal to zero. Ignoring." % p_new_slot_count)
		return excess_items_array

	if p_new_slot_count != INFINITE_SIZE:
		# The inventory is currently of finite size. We need to extract the excess items that can be found after the new size (if any)
		var available_slots: int = __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())
		if p_new_slot_count < available_slots:
			for slot_number: int in available_slots - p_new_slot_count:
				var slot_to_process: int = slot_number + p_new_slot_count
				if __is_slot_empty(slot_to_process):
					continue

				# The slot is not empty. This slot is now an excess items object:
				var item_id: int = __get_slot_item_id(slot_to_process)
				var item_amount: int = __get_slot_item_amount(slot_to_process)
				var item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_to_process, null)
				var excess_items: ExcessItems = __create_excess_items(item_id, item_amount, item_instance_data)
				excess_items_array.push_back(excess_items)

				# And remove those from the inventory to update the internal counters:
				var _result_is_zero: int = __remove_items_from_slot(slot_to_process, item_id, item_amount, item_instance_data)

		# Resize the slots data:
		var last_slot_index: int = p_new_slot_count - 1
		var new_array_size: int = __calculate_array_size_needed_to_access_slot_index(last_slot_index)
		var _error: int = _m_item_slots_packed_array.resize(new_array_size)
		if _error != OK:
			push_warning("InventoryManager: unable to resize slots array to the desired size.")

	# Track the new size:
	__set_size(p_new_slot_count)

	# Synchronize change with the debugger:
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			EngineDebugger.send_message("inventory_manager:resize", [get_instance_id(), p_new_slot_count])
	return excess_items_array


# Adds items to the specified slot number. Returns the number of items not added to the slot.
# NOTE: The slot number is assumed to be within bounds in this function.
# NOTE: Assumes the passed instance data is already normalized (i.e. p_instance_data is null if the fallback data is the same)
func __add_items_to_slot(p_slot_index: int, p_item_id: int, p_amount: int, p_instance_data: Variant) -> int:
	var was_slot_empty: int = __is_slot_empty(p_slot_index)
	if was_slot_empty:
		# The slot was empty. Inject the item id.
		var item_id_index: int = __calculate_slot_item_id_index(p_slot_index)
		_m_item_slots_packed_array[item_id_index] = p_item_id
	var amount_to_add: int = clampi(p_amount, -1, __get_remaining_slot_capacity(p_slot_index, p_item_id))
	if amount_to_add == -1:
		return p_amount
	var item_amount_index: int = __calculate_slot_item_amount_index(p_slot_index)
	_m_item_slots_packed_array[item_amount_index] = __get_slot_item_amount(p_slot_index) + amount_to_add
	if was_slot_empty:
		__increase_stack_count(p_item_id)
		__add_item_id_slot_to_tracker(p_item_id, p_slot_index)
		if p_instance_data != null:
			_m_item_slots_instance_data_tracker[p_slot_index] = p_instance_data
		item_added.emit(p_slot_index, p_item_id)
	slot_modified.emit(p_slot_index)
	var remaining_amount_to_add: int = p_amount - amount_to_add
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			var item_manager_id: int = get_instance_id()
			var stringified_instance_data : String = str(p_instance_data)
			EngineDebugger.send_message("inventory_manager:add_items_to_slot", [item_manager_id, p_slot_index, p_item_id, p_amount, stringified_instance_data])
	return remaining_amount_to_add


# Sets the size of the inventory.
func __set_size(p_new_size: int) -> void:
	if p_new_size == _DEFAULT_SIZE:
		var _success: int = _m_inventory_manager_dictionary.erase(_key.SIZE)
	else:
		_m_inventory_manager_dictionary[_key.SIZE] = p_new_size


# Removes items from the specified slot number. Returns the number of items not removed from the slot.
# NOTE: The slot number is assumed to be within bounds in this function.
func __remove_items_from_slot(p_slot_index: int, p_item_id: int, p_amount: int, p_instance_data: Variant) -> int:
	var item_amount: int = __get_slot_item_amount(p_slot_index)
	var amount_to_remove: int = clampi(p_amount, 0, item_amount)
	var new_amount: int = item_amount - amount_to_remove
	_m_item_slots_packed_array[__calculate_slot_item_amount_index(p_slot_index)] = new_amount
	if new_amount == 0:
		__decrease_stack_count(p_item_id)
		__remove_item_id_slot_from_tracker(p_item_id, p_slot_index)
		var _success: bool = _m_item_slots_instance_data_tracker.erase(p_slot_index)
		item_removed.emit(p_slot_index, p_item_id)
	slot_modified.emit(p_slot_index)
	var remaining_amount_to_remove: int = p_amount - amount_to_remove
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			var item_manager_id: int = get_instance_id()
			var stringified_instance_data : String = str(p_instance_data)
			EngineDebugger.send_message("inventory_manager:remove_items_from_slot", [item_manager_id, p_slot_index, p_item_id, p_amount, stringified_instance_data])
	return remaining_amount_to_remove


# Increases the inventory to fix at most the passed slot number.
# NOTE: The slot number is assumed to be within bounds in this function.
func __increase_size(p_slot_index: int) -> void:
	var expected_new_size: int = __calculate_array_size_needed_to_access_slot_index(p_slot_index)
	var error: int = _m_item_slots_packed_array.resize(expected_new_size)
	if error != OK:
		push_warning("InventoryManager: Unable to resize inventory properly. New inventory size is: %d. Expected size: %d." % [_m_item_slots_packed_array.size(), expected_new_size])


# Returns the item ID for the given item slot.
# NOTE: The slot number is assumed to be within bounds in this function.
func __get_slot_item_id(p_slot_index: int) -> int:
	var p_slot_item_id_index: int = __calculate_slot_item_id_index(p_slot_index)
	return _m_item_slots_packed_array[p_slot_item_id_index]


# Returns the item amount for the given item slot. Returns 0 on empty slots.
# NOTE: The slot number is assumed to be within bounds in this function.
func __get_slot_item_amount(p_slot_index: int) -> int:
	var slot_item_amount_index: int = __calculate_slot_item_amount_index(p_slot_index)
	var amount: int = clampi(_m_item_slots_packed_array[slot_item_amount_index], 0, _INT64_MAX)
	return amount


# Sets the slot item instance data
# NOTE: The slot number is assumed to be within bounds in this function.
func __set_slot_item_instance_data(p_slot_index: int, p_item_instance_data: Variant) -> void:
	var item_id: int = __get_slot_item_id(p_slot_index)
	var item_instance_data_comparator : Callable = _m_item_registry.get_instance_data_comparator(item_id)
	var registered_item_instance_data: Variant = _m_item_registry.get_instance_data(item_id)
	var are_instance_data_the_same: bool = item_instance_data_comparator.call(registered_item_instance_data, p_item_instance_data)
	if are_instance_data_the_same:
		var _success: bool = _m_item_slots_instance_data_tracker.erase(p_slot_index)
		return
	_m_item_slots_instance_data_tracker[p_slot_index] = p_item_instance_data


# Returns the remaining amount of items this slot can hold. Returns -1 on mismatching item ids.
# NOTE: The slot number is assumed to be within bounds in this function.
# NOTE: The item instance data is assumed to be correct.
func __get_remaining_slot_capacity(p_slot_index: int, p_item_id: int) -> int:
	var item_id: int = __get_slot_item_id(p_slot_index)
	if item_id != p_item_id:
		# Mismatching ids. It's impossible to add items of the specified item ID to this slot.
		return -1
	var amount: int = __get_slot_item_amount(p_slot_index)
	var stack_capacity: int = _m_item_registry.get_stack_capacity(item_id)
	var remaining_capacity: int = clampi(stack_capacity - amount, 0, stack_capacity)
	return remaining_capacity


# Returns true when the item slot is is empty. Returns false otherwise. Checking if the slot is empty does not mean it is valid or reachable if the inventory is strictly sized.
# NOTE: The slot number is assumed to be within bounds in this function.
func __is_slot_empty(p_slot_index: int) -> bool:
	var slot_item_amount: int = __get_slot_item_amount(p_slot_index)
	return slot_item_amount <= 0


# Returns true if the slot has been allocated in memory. Returns false otherwise.
func __is_slot_allocated(p_slot_index: int) -> bool:
	return p_slot_index < __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())


# Given a slot number, calculates the index for the item ID index of that slot.
func __calculate_slot_item_id_index(p_slot_index: int) -> int:
	return p_slot_index * 2


# Given a slot number, calculates the index for the item amount index of that slot.
func __calculate_slot_item_amount_index(p_slot_index: int) -> int:
	return clampi(p_slot_index * 2 + 1, 0, _INT64_MAX)


# Given a slot number, returns the minimum array size needed to fit that slot number.
func __calculate_array_size_needed_to_access_slot_index(p_slot_index: int) -> int:
	return clampi(p_slot_index * 2 + 2, 0, _INT64_MAX)


# Given a slot number, returns the minimum array size needed to fit that slot number.
func __calculate_slot_numbers_given_array_size(p_array_size: int) -> int:
	@warning_ignore("integer_division")
	return p_array_size / 2


## Returns the number of slots inventory has. If the inventory is set to infinite size, returns the number of slots currently allocated in memory.[br][br]
## To check if the inventory is set to infinite size, use [method is_infinite].[br][br]
## To always return the number of slots allocated in memory, use [method slots].
func size() -> int:
	if is_infinite():
		return __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())
	else:
		var inventory_size: int = _m_inventory_manager_dictionary.get(_key.SIZE, _DEFAULT_SIZE)
		return inventory_size


## Returns the number of slots allocated in memory.
func slots() -> int:
	return __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())


## Returns true if the inventory is finite or limited. Returns false if the inventory is set to infinite size.
func is_infinite() -> bool:
	var inventory_size: int = _m_inventory_manager_dictionary.get(_key.SIZE, _DEFAULT_SIZE)
	return inventory_size == INFINITE_SIZE


## Returns the item registry the inventory manager was initialized with.
func get_item_registry() -> ItemRegistry:
	return _m_item_registry


## Sets a name to the manager. Only used for identifying the inventory in the debugger.
func set_name(p_name: String) -> void:
	set_meta(&"name", p_name)
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			EngineDebugger.send_message("inventory_manager:set_name", [get_instance_id(), p_name])


## Gets the name of the manager.
func get_name() -> String:
	return get_meta(&"name", "")


## Returns true if the inventory can handle the item in question. Returns false otherwise. This function is a wrapper around [method ItemRegistry.has_item], specifically for inventory manager instances should only handle items from the registry.
func is_item_registered(p_item_id: int) -> bool:
	return _m_item_registry.has_item(p_item_id)


## Returns a duplicated slots array with internal keys replaced with strings for easier reading/debugging.[br]
## [br]
## [b]Example[/b]:
## [codeblock]
## var inventory_manager : InventoryManager = InventoryManager.new()
## var inventory_manager.add(0, 0)
## print(JSON.stringify(inventory_manager.prettify(), "\t"))
## [/codeblock]
func prettify() -> Array:
	var prettified_data: Array = []
	for slot_number: int in __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size()):
		if __is_slot_empty(slot_number):
			continue

		var item_id: int = __get_slot_item_id(slot_number)
		var item_amount: int = __get_slot_item_amount(slot_number)

		var readable_dictionary: Dictionary = { }

		# ItemRegistry data:
		var name: String = _m_item_registry.get_name(item_id)
		if not name.is_empty():
			readable_dictionary["name"] = name
		var description: String = _m_item_registry.get_description(item_id)
		if not description.is_empty():
			readable_dictionary["description"] = description
		var registry_entry_metadata: Dictionary = _m_item_registry.get_registry_metadata_data()
		if not registry_entry_metadata.is_empty():
			readable_dictionary["metadata"] = registry_entry_metadata

		# Slot data:
		readable_dictionary["slot"] = slot_number
		readable_dictionary["item_id"] = item_id
		readable_dictionary["amount"] = item_amount

		prettified_data.push_back(readable_dictionary)
	return prettified_data


## Returns a dictionary of all the data processed by the manager. Use [method set_data] initialize an inventory back to the extracted data.[br]
## [br]
## [color=yellow]Warning:[/color] Use with caution. Modifying this dictionary will directly modify the inventory manager data.
func get_data() -> Dictionary:
	return _m_inventory_manager_dictionary


## Sets the inventory manager data.
func set_data(p_data: Dictionary) -> void:
	# Clear the inventory.
	clear()

	# Inject the new data.
	_m_inventory_manager_dictionary = p_data

	# Update data references used all over the manager code.
	_m_item_slots_packed_array = _m_inventory_manager_dictionary[_key.ITEM_SLOTS]
	_m_item_slots_instance_data_tracker = _m_inventory_manager_dictionary[_key.INSTANCE_DATA_TRACKER]

	# Send a signal about all the new slots that changed and also count the stacks.
	for slot_number: int in __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size()):
		if __is_slot_empty(slot_number):
			continue
		var item_id: int = __get_slot_item_id(slot_number)
		__increase_stack_count(item_id)
		__add_item_id_slot_to_tracker(item_id, slot_number)
		item_added.emit(slot_number, item_id)
		slot_modified.emit(slot_number)

	# Data is not auto-fixed. Do a sanity check only on debug builds to report the issues.
	if OS.is_debug_build():
		var sanity_check_messages: PackedStringArray = sanity_check()
		var joined_messages: String = "".join(sanity_check_messages)
		if not joined_messages.is_empty():
			push_warning("InventoryManager: Found the following issues in the inventory:\n%s" % joined_messages)


	# Synchronize change with the debugger.
	if EngineDebugger.is_active():
		if not has_meta(&"deregistered"):
			EngineDebugger.send_message("inventory_manager:set_data", [get_instance_id(), _m_inventory_manager_dictionary])


## Automatically applies the item registry constraints to the inventory. Returns an array of excess items found, if any.
func apply_registry_constraints() -> Array[ExcessItems]:
	# Extract excess items if any
	var excess_items_array: Array[ExcessItems] = []
	var item_id_to_stack_count_map: Dictionary = { }
	for slot_number: int in __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size()):
		if __is_slot_empty(slot_number):
			# Nothing to do here.
			continue

		# Track item stack count
		var item_id: int = __get_slot_item_id(slot_number)
		var stack_count: int = item_id_to_stack_count_map.get(item_id, 0) + 1
		item_id_to_stack_count_map[item_id] = stack_count
		var registry_stack_count: int = _m_item_registry.get_stack_count(item_id)

		# Extract the excess items from the stack if any:
		var excess_items: ExcessItems = null
		var registry_stack_capacity: int = _m_item_registry.get_stack_capacity(item_id)
		var item_amount: int = __get_slot_item_amount(slot_number)
		if item_amount > registry_stack_capacity:
			var excess_item_amount: int = item_amount - registry_stack_capacity
			var item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
			excess_items = __create_excess_items(item_id, excess_item_amount, item_instance_data)
			var _result_is_zero: int = __remove_items_from_slot(slot_number, item_id, excess_item_amount, item_instance_data)

		if is_instance_valid(excess_items):
			excess_items_array.push_back(excess_items)

		# If the item stack count is limited and we are over the stack count limit, the whole stack is an excess items.
		if _m_item_registry.is_stack_count_limited(item_id) and stack_count > registry_stack_count:
			# Then convert the whole item slot into excess items
			# NOTE: Re-read the current slot amount since it may have been reduced by the stack capacity check above.
			var current_item_amount: int = __get_slot_item_amount(slot_number)
			var item_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
			var excess_stack: ExcessItems = __create_excess_items(item_id, current_item_amount, item_instance_data)
			if is_instance_valid(excess_stack):
				excess_items_array.push_back(excess_stack)

			# Empty the slot.
			var _result_is_zero: int = __remove_items_from_slot(slot_number, item_id, current_item_amount, item_instance_data)
	return excess_items_array


## Preforms a sanity check over the data.
func sanity_check() -> PackedStringArray:
	# Extract excess items if any
	var item_id_to_stack_count_map: Dictionary = { }
	var message_array: PackedStringArray = PackedStringArray()
	var new_size: int = __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size())
	var _error: int = message_array.resize(new_size)
	var message_array_index: int = 0
	for slot_number: int in new_size:
		if __is_slot_empty(slot_number):
			continue

		var message: String = ""

		# Check if item is registered in registry:
		var item_id: int = __get_slot_item_id(slot_number)
		var item_registry: ItemRegistry = get_item_registry()
		if not item_registry.has_item(item_id):
			message += "Slot %d: Could not find item ID \'%d\' in associated registry.\n" % [slot_number, item_id]

		# Track item stack count:
		var stack_count: int = item_id_to_stack_count_map.get(item_id, 0) + 1
		item_id_to_stack_count_map[item_id] = stack_count
		var registry_stack_count: int = _m_item_registry.get_stack_count(item_id)

		# Check if the slot has excess items and warn about these as well:
		if __does_slot_have_excess_items(slot_number):
			var registry_stack_capacity: int = _m_item_registry.get_stack_capacity(item_id)
			message += "Slot %d: Stack with item ID '%d' has excess items. Current stack capacity: %d. Registered stack capacity: %d.\n" % [slot_number, item_id, __get_slot_item_amount(slot_number), registry_stack_capacity]

		# If the stack count is limited and greater than the registered stack count, the stack shouldn't be present in the inventory:
		if _m_item_registry.is_stack_count_limited(item_id) and stack_count > registry_stack_count:
			message += "Slot %d: Stack with item ID '%d' should not be present since the max stack count has already been reached.\n" % [slot_number, item_id]

		message_array[message_array_index] = message
		message_array_index += 1
	return message_array


# Returns the true if the item slot has excess items. Returns false otherwise.
func __does_slot_have_excess_items(p_slot_index: int) -> bool:
	var item_id: int = __get_slot_item_id(p_slot_index)
	var registered_stack_capacity: int = _m_item_registry.get_stack_capacity(item_id)
	var item_amount: int = __get_slot_item_amount(p_slot_index)
	return item_amount > registered_stack_capacity


## Returns the count of empty slots.
func get_empty_slot_count() -> int:
	var inventory_size: int = size()
	if is_infinite():
		inventory_size = _INT64_MAX
	var total_slots_filled: int = 0
	for stack_count: int in _m_item_stack_count_tracker.values():
		total_slots_filled += stack_count
	return inventory_size - total_slots_filled


## Returns the remaining item capacity for the specified item ID.
func get_remaining_capacity_for_item(p_item_id: int, p_instance_data: Variant = null) -> int:
	if size() == 0 and not is_infinite():
		return 0

	# Make sure to always fallback instance data to whatever is on the registry:
	p_instance_data = __make_instance_data_null_if_same_as_fallback(p_item_id, p_instance_data)

	# Check if the inventory is infinite because then that simplifies this operation.
	if is_infinite():
		if not _m_item_registry.is_stack_count_limited(p_item_id):
			# There's no limit to the number of stacks. The amount we can store of this item is infinite.
			return _INT64_MAX

	# Get the remaining item capacity within all the slot:
	var remaining_item_capacity_within_slots: int = 0
	var registered_stack_capacity: int = _m_item_registry.get_stack_capacity(p_item_id)
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
	for slot_number: int in item_id_slots_array:
		var slot_instance_data: Variant = _m_item_slots_instance_data_tracker.get(slot_number, null)
		if registered_instance_data_comparator.call(p_instance_data, slot_instance_data):
			var remaining_slot_capacity: int = clampi(registered_stack_capacity - get_slot_item_amount(slot_number), 0, registered_stack_capacity)
			remaining_item_capacity_within_slots += remaining_slot_capacity

	# Count the remaining stack count
	var registered_stack_count: int = _m_item_registry.get_stack_count(p_item_id)
	var item_stack_count: int = _m_item_stack_count_tracker.get(p_item_id, 0)
	var remaining_stack_count: int = registered_stack_count - item_stack_count
	if not _m_item_registry.is_stack_count_limited(p_item_id):
		# The stack count is not limited. Infinitely many items can be added to the inventory.
		remaining_stack_count = _INT64_MAX

	# Clamp the remaining stacks to the available slots left:
	var remaining_stack_count_limited_by_empty_slot_count: int = clampi(remaining_stack_count, 0, get_empty_slot_count())

	# Calculate the remaining capacity
	var remaining_capacity: int = remaining_stack_count_limited_by_empty_slot_count * registered_stack_capacity + remaining_item_capacity_within_slots
	if remaining_capacity < 0:
		# The remaining_capacity calculation above overflowed. Reset back to max value.
		remaining_capacity = _INT64_MAX
	return remaining_capacity


## Organizes the inventory by maximizing its space usage and moving items closer to the beginning of the inventory by avoiding empty slots. [br]
## If an array of item IDs is passed to the function, the items will be organized in the order found within the array.
func organize(p_item_ids_array: PackedInt64Array = []) -> void:
	# Duplicate internal data before reorganizing
	var item_slots_packed_array: PackedInt64Array = _m_item_slots_packed_array.duplicate()
	var item_slots_tracker: Dictionary = _m_item_slots_tracker.duplicate()
	var item_slots_instance_data_tracker: Dictionary = _m_item_slots_instance_data_tracker.duplicate()

	# Clear all the data but keep the inventory memory allocated to the same size
	clear()

	# Re-add the items to the inventory:
	if p_item_ids_array.is_empty():
		# No specific sorting. Use the item IDs themselves as a sorting value.
		var sorted_item_ids: PackedInt64Array = item_slots_tracker.keys()
		sorted_item_ids.sort()
		for item_id: int in sorted_item_ids:
			var slots_where_item_was_installed: PackedInt64Array = item_slots_tracker[item_id]
			for slot_number: int in slots_where_item_was_installed:
				var item_amount_index: int = __calculate_slot_item_amount_index(slot_number)
				var amount: int = item_slots_packed_array[item_amount_index]
				var instance_data: Variant = item_slots_instance_data_tracker.get(slot_number, null)
				var excess_items: ExcessItems = add(item_id, amount, instance_data)
				if is_instance_valid(excess_items):
					push_warning("InventoryManager: Stumbled upon excess items upon inventory reorganization.\n%s\n" % excess_items)
	else:
		# Specific sorting given. Track unprocessed item IDs.
		var item_ids_not_processed: PackedInt64Array = item_slots_tracker.keys()
		for item_id: int in p_item_ids_array:
			if item_slots_tracker.has(item_id):
				var slots_where_item_was_installed: PackedInt64Array = item_slots_tracker[item_id]
				for slot_number: int in slots_where_item_was_installed:
					var item_amount_index: int = __calculate_slot_item_amount_index(slot_number)
					var amount: int = item_slots_packed_array[item_amount_index]
					var instance_data: Variant = item_slots_instance_data_tracker.get(slot_number, null)
					var excess_items: ExcessItems = add(item_id, amount, instance_data)
					if is_instance_valid(excess_items):
						push_warning("InventoryManager: Stumbled upon excess items upon inventory reorganization.\n%s\n" % excess_items)
				var index_found: int = item_ids_not_processed.find(item_id)
				if index_found != -1:
					item_ids_not_processed.remove_at(index_found)
		item_ids_not_processed.sort()
		if not item_ids_not_processed.is_empty():
			var message_format: String = "InventoryManager: organize function called with a list of item IDs but not all the item IDs were found.\n"
			message_format += "\tHere are the missing item IDs that will be ordered as they appear:\n"
			message_format += "\t%s"
			push_warning(message_format % item_ids_not_processed)
		for item_id: int in item_ids_not_processed:
			var slots_where_item_was_installed: PackedInt64Array = item_slots_tracker[item_id]
			for slot_number: int in slots_where_item_was_installed:
				var item_amount_index: int = __calculate_slot_item_amount_index(slot_number)
				var amount: int = item_slots_packed_array[item_amount_index]
				var instance_data: Variant = item_slots_instance_data_tracker.get(slot_number, null)
				var excess_items: ExcessItems = add(item_id, amount, instance_data)
				if is_instance_valid(excess_items):
					push_warning("InventoryManager: Stumbled upon excess items upon inventory reorganization.\n%s\n" % excess_items)

	# Emit signals for all the slots changed, and resize the slots array to fit only the used item slots to save memory.
	var last_slot_number_filled: int = -1
	for slot_number: int in __calculate_slot_numbers_given_array_size(_m_item_slots_packed_array.size()):
		if __is_slot_empty(slot_number):
			break
		slot_modified.emit(slot_number)
		last_slot_number_filled = slot_number
	var expected_size: int = 0
	if last_slot_number_filled >= 0:
		expected_size = __calculate_array_size_needed_to_access_slot_index(last_slot_number_filled)
	var error: int = _m_item_slots_packed_array.resize(expected_size)
	if error != OK:
		push_warning("InventoryManager: slot array resize did not go as expected within organize(). Got new size %d, but expected %d." % [_m_item_slots_packed_array.size(), expected_size])


## Clears the inventory. Keeps the current size.
func clear() -> void:
	_m_item_slots_packed_array.fill(0)
	_m_item_stack_count_tracker.clear()
	_m_item_slots_tracker.clear()
	_m_item_slots_instance_data_tracker.clear()
	inventory_cleared.emit()


## Deregisters the inventory manager from the debugger.
func deregister() -> void:
	if EngineDebugger.is_active():
		set_meta(&"deregistered", true)
		if inventory_cleared.is_connected(__synchronize_inventory_with_debugger_when_cleared):
			inventory_cleared.disconnect(__synchronize_inventory_with_debugger_when_cleared)
		EngineDebugger.send_message("inventory_manager:deregister_inventory_manager", [get_instance_id()])


# Creates and returns an [ExcessItems] object meant to represent either the unprocessed addition or removal of items from the inventory.
func __create_excess_items(p_item_id: int, p_amount: int, p_instance_data: Variant) -> ExcessItems:
	assert(p_amount >= 0, "InventoryManager: excess item amount upon creation is less than zero. This should not happen.")
	if p_amount == 0:
		return null
	return ExcessItems.new(_m_item_registry, p_item_id, p_amount, p_instance_data)


# Function used by the debugger only. Used to increase the InventoryManager data arrays if needed.
func __allocate_if_needed(p_slot_index: int) -> void:
	if not __is_slot_allocated(p_slot_index):
		__increase_size(p_slot_index)


# Every time an item slot is modified, synchronize it with the debugger
func __synchronize_inventory_with_debugger_when_cleared() -> void:
	var item_manager_id: int = get_instance_id()
	EngineDebugger.send_message("inventory_manager:clear", [item_manager_id])


# Increases the item id stack count.
func __increase_stack_count(p_item_id: int) -> void:
	_m_item_stack_count_tracker[p_item_id] = _m_item_stack_count_tracker.get(p_item_id, 0) + 1


# Decreases the item id stack count.
func __decrease_stack_count(p_item_id: int) -> void:
	var new_stack_count: int = _m_item_stack_count_tracker.get(p_item_id, 0) - 1
	if new_stack_count == 0:
		var _erase_success: bool = _m_item_stack_count_tracker.erase(p_item_id)
	else:
		_m_item_stack_count_tracker[p_item_id] = new_stack_count


# Adds a slot to the item id slot tracker
func __add_item_id_slot_to_tracker(p_item_id: int, p_slot_index: int) -> void:
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker.get(p_item_id, PackedInt64Array())
	var was_empty: bool = item_id_slots_array.is_empty()
	var _success: bool = item_id_slots_array.push_back(p_slot_index)
	if was_empty:
		_m_item_slots_tracker[p_item_id] = item_id_slots_array


# Removes a slot from the item id slot tracker
func __remove_item_id_slot_from_tracker(p_item_id: int, p_slot_index: int) -> void:
	var item_id_slots_array: PackedInt64Array = _m_item_slots_tracker[p_item_id]
	var index_to_remove: int = item_id_slots_array.find(p_slot_index)
	assert(index_to_remove != -1, "InventoryManager: could not find item id index for slot tracker removal. This should not happen. Please file a bug.")
	item_id_slots_array.remove_at(index_to_remove)
	if item_id_slots_array.is_empty():
		var _success: bool = _m_item_slots_tracker.erase(p_item_id)


func _to_string() -> String:
	return "<InventoryManager#%d> Size: %d, Allocated Slots: %d" % [get_instance_id(), size(), slots()]


# Make instance data null if the same as fallback -- we use this since we always fallback to registered instance data when inventory manager has none.
func __make_instance_data_null_if_same_as_fallback(p_item_id: int, p_instance_data: Variant) -> Variant:
	if p_instance_data == null:
		# There's nothing to do here. The instance data passed is already null meaning we don't need to use the fallback comparator.
		return null
	var registered_instance_data: Variant = _m_item_registry.get_instance_data(p_item_id)
	if registered_instance_data == null:
		# The registered instance data is null, but the passed instance data is not. The comparison is already processed -- the passed instance data has priority.
		return p_instance_data

	# Need to compare the registered instance data with the passed instance data:
	var registered_instance_data_comparator: Callable = _m_item_registry.get_instance_data_comparator(p_item_id)
	if registered_instance_data_comparator.call(registered_instance_data, p_instance_data):
		push_warning("InventoryManager: The registered instance data is the same as the passed instance data -- there's no need to install any instance data in this particular case. Ignoring passed data.")
		return null
	else:
		# The target instance data differs -- we need to install this passed instance data which has priority
		return p_instance_data


func _init(p_item_registry: ItemRegistry = null) -> void:
	_m_item_registry = p_item_registry
	_m_inventory_manager_dictionary[_key.ITEM_SLOTS] = _m_item_slots_packed_array
	_m_inventory_manager_dictionary[_key.INSTANCE_DATA_TRACKER] = _m_item_slots_instance_data_tracker

	if not is_instance_valid(_m_item_registry):
		_m_item_registry = ItemRegistry.new()
	if EngineDebugger.is_active():
		# Register with the debugger
		var current_script: Resource = get_script()
		var path: String = current_script.get_path()
		var name: String = get_name()
		EngineDebugger.send_message("inventory_manager:register_inventory_manager", [get_instance_id(), name, path, _m_item_registry.get_instance_id()])

		# Update remote
		var _success: int = inventory_cleared.connect(__synchronize_inventory_with_debugger_when_cleared)
