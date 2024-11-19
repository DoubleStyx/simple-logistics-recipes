local production_and_logistics_items = {}

for name, item in pairs(data.raw["item"]) do
    if item.subgroup then
        local subgroup = data.raw["item-subgroup"][item.subgroup]
        if subgroup and subgroup.group then
            local group_name = subgroup.group
            if group_name == "logistics" or group_name == "production" then
                table.insert(production_and_logistics_items, item)
            end
        end
    end
end

local function is_raw_material(ingredient_name, ingredient_type)
    if ingredient_type == "item" then
        return not data.raw["recipe"][ingredient_name]
    elseif ingredient_type == "fluid" then
        return not data.raw["recipe"][ingredient_name]
    end
    return false
end

local function calculate_total_raw_cost(item_name, item_type, visited)
    visited = visited or {}
    local key = item_type .. ":" .. item_name
    if visited[key] then
        return 0
    end
    visited[key] = true

    if is_raw_material(item_name, item_type) then
        visited[key] = nil
        return 1
    end

    local recipe = data.raw["recipe"][item_name]
    if not recipe or not recipe.ingredients then
        visited[key] = nil
        return 1
    end

    local total_raw_input = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local amount = ingredient.amount
            or (ingredient.amount_min + ingredient.amount_max) / 2
            or 1
        local ing_name = ingredient.name or ingredient[1]
        local ing_type = ingredient.type or "item"
        local sub_cost = calculate_total_raw_cost(ing_name, ing_type, visited)
        total_raw_input = total_raw_input + amount * sub_cost
    end

    local total_output = 1
    if recipe.result_count then
        total_output = recipe.result_count
    elseif recipe.results and recipe.results[1] and recipe.results[1].amount then
        total_output = recipe.results[1].amount
    end

    visited[key] = nil

    return total_raw_input / total_output
end

local function get_most_expensive_ingredient(recipe)
    local highest_raw_cost = -math.huge
    local selected_ingredient = nil

    for _, ingredient in pairs(recipe.ingredients) do
        local ing_name = ingredient.name or ingredient[1]
        local ing_type = ingredient.type or "item"
        local raw_cost = calculate_total_raw_cost(ing_name, ing_type)

        if raw_cost > highest_raw_cost then
            highest_raw_cost = raw_cost
            selected_ingredient = {name = ing_name, type = ing_type, raw_cost = raw_cost}
        end
    end

    return selected_ingredient
end




local function modify_recipe(recipe, winner, total_item_raw_cost)
    local scale = total_item_raw_cost / winner.raw_cost
    local scaled_quantity = math.ceil(scale)
    
    local max_value = 65535
    scaled_quantity = math.min(scaled_quantity, max_value)

    recipe.ingredients = {
        {type = winner.type, name = winner.name, amount = scaled_quantity}
    }
end

for _, item in pairs(production_and_logistics_items) do
    local recipe = data.raw["recipe"][item.name]
    if recipe and recipe.ingredients then
        local total_item_raw_cost = calculate_total_raw_cost(item.name, "item")

        local winner = get_most_expensive_ingredient(recipe)
        if winner then
            modify_recipe(recipe, winner, total_item_raw_cost)
        end
    end
end