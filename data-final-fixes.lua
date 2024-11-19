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

local function calculate_rcr(ingredient_name, ingredient_type, visited)
    visited = visited or {}
    if visited[ingredient_name] then
        return 0
    end
    visited[ingredient_name] = true

    if is_raw_material(ingredient_name, ingredient_type) then
        visited[ingredient_name] = nil
        return 1
    end

    local recipe = data.raw["recipe"][ingredient_name]
    if not recipe then
        visited[ingredient_name] = nil
        return 1
    end

    local total_raw_input = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local amount = ingredient.amount
            or (ingredient.amount_min + ingredient.amount_max) / 2
            or 1
        local sub_rcr = calculate_rcr(ingredient.name, ingredient.type or "item", visited)
        total_raw_input = total_raw_input + amount * sub_rcr
    end

    local total_output = 1
    if recipe.result_count then
        total_output = recipe.result_count
    elseif recipe.results and recipe.results[1] and recipe.results[1].amount then
        total_output = recipe.results[1].amount
    end

    visited[ingredient_name] = nil

    return total_raw_input / total_output
end

local function get_highest_rcr_ingredient(recipe)
    local highest_rcr = -math.huge
    local selected_ingredient = nil

    for _, ingredient in pairs(recipe.ingredients) do
        local ingredient_name = ingredient.name or ingredient[1]
        local ingredient_type = ingredient.type or "item"
        local rcr = calculate_rcr(ingredient_name, ingredient_type)

        if rcr > highest_rcr then
            highest_rcr = rcr
            selected_ingredient = {name = ingredient_name, type = ingredient_type}
        end
    end

    return selected_ingredient, highest_rcr
end



local function modify_recipe(recipe, winner, scaled_quantity)
    recipe.ingredients = {
        {type = winner.type, name = winner.name, amount = scaled_quantity}
    }
end

for _, item in pairs(production_and_logistics_items) do
    local recipe = data.raw["recipe"][item.name]
    if recipe and recipe.ingredients then
        local winner, highest_rcr = get_highest_rcr_ingredient(recipe)
        if winner then
            local scaled_quantity = math.ceil(highest_rcr)
            modify_recipe(recipe, winner, scaled_quantity)
        end
    end
end
