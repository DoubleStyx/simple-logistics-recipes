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

local function is_raw_material(ingredient_name)
    local raw_materials = {
        ["iron-ore"] = true,
        ["copper-ore"] = true,
        ["coal"] = true,
        ["stone"] = true,
        ["oil"] = true,
    }
    return raw_materials[ingredient_name] or false
end

local complexity_cache = {}

local function calculate_complexity(ingredient_name, visited)
    visited = visited or {}
    if visited[ingredient_name] then
        return {depth = 0, quantity = 1}
    end
    visited[ingredient_name] = true

    if complexity_cache[ingredient_name] then
        return complexity_cache[ingredient_name]
    end

    if is_raw_material(ingredient_name) then
        complexity_cache[ingredient_name] = {depth = 0, quantity = 1}
        return complexity_cache[ingredient_name]
    end

    local recipe = data.raw["recipe"][ingredient_name]

    if not recipe then
        complexity_cache[ingredient_name] = {depth = 0, quantity = 1}
        return complexity_cache[ingredient_name]
    end

    local max_depth = 0
    local total_quantity = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local comp = calculate_complexity(ingredient.name, visited)
        max_depth = math.max(max_depth, comp.depth)
        total_quantity = total_quantity + comp.quantity
    end

    complexity_cache[ingredient_name] = {depth = max_depth + 1, quantity = total_quantity}
    return complexity_cache[ingredient_name]
end

local cost_cache = {}

local function calculate_raw_material_cost(ingredient_name, amount, visited)
    log("uwu")
    visited = visited or {}
    
    if visited[ingredient_name] then
        return 0
    end
    visited[ingredient_name] = true
    
    if cost_cache[ingredient_name] then
        visited[ingredient_name] = nil  -- Clean up before returning
        return cost_cache[ingredient_name] * amount
    end

    if is_raw_material(ingredient_name) then
        cost_cache[ingredient_name] = 1
        visited[ingredient_name] = nil
        return amount
    end

    local recipe = data.raw["recipe"][ingredient_name]

    if not recipe then
        cost_cache[ingredient_name] = 1
        visited[ingredient_name] = nil
        return amount
    end

    local total_cost = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local ingredient_amount = (ingredient.amount or (ingredient.amount_min + ingredient.amount_max) / 2) or 1
        total_cost = total_cost + calculate_raw_material_cost(ingredient.name, ingredient_amount, visited)  -- Pass 'visited' here
    end

    local output_amount = 1
    if recipe.result_count then
        output_amount = recipe.result_count
    elseif recipe.results and recipe.results[1] and recipe.results[1].amount then
        output_amount = recipe.results[1].amount
    end

    total_cost = total_cost / output_amount

    cost_cache[ingredient_name] = total_cost
    visited[ingredient_name] = nil  -- Clean up before returning
    return total_cost * amount
end


local function get_most_complex_ingredient(recipe)
    local winner = nil
    local winner_complexity = nil

    for _, ingredient in pairs(recipe.ingredients) do
        local comp = calculate_complexity(ingredient.name)

        if not winner_complexity or 
           comp.depth > winner_complexity.depth or
           (comp.depth == winner_complexity.depth and comp.quantity > winner_complexity.quantity) then
            winner = ingredient
            winner_complexity = comp
        end
    end

    return winner
end

local function calculate_total_raw_cost(recipe)
    local total_cost = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local amount = (ingredient.amount or (ingredient.amount_min + ingredient.amount_max) / 2) or 1
        total_cost = total_cost + calculate_raw_material_cost(ingredient.name, amount)
    end

    return total_cost
end

local function modify_recipe(recipe, winner, scaled_quantity)
    recipe.ingredients = {
        {type = "item", name = winner.name, amount = scaled_quantity}
    }
end

for _, item in pairs(production_and_logistics_items) do
    local recipe = data.raw["recipe"][item.name]
    log("Recipe: " .. item.name)
    if recipe and recipe.ingredients then
        local winner = get_most_complex_ingredient(recipe)
        if winner then
            local total_raw_cost = calculate_total_raw_cost(recipe)
            local winner_raw_cost = calculate_raw_material_cost(winner.name, 1)
            local scaling_factor = total_raw_cost / calculate_raw_material_cost(winner.name, recipe.results[1].amount)            
            local scaled_quantity = math.ceil(scaling_factor)
            modify_recipe(recipe, winner, scaled_quantity)
        end
    end
end