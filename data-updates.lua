local function replace_ingredient(ingredients, old_ingredient, new_ingredient)
    for i, ingredient in pairs(ingredients) do
        if ingredient.name then
            if ingredient.name == old_ingredient then
                ingredient.name = new_ingredient
            end
        end
    end
end

local function replace_results(results, old_result, new_result)
    for i, result in pairs(results) do
        if result.name then
            if result.name == old_result then
                result.name = new_result
            end
        end
    end
end

local function update_recipe(recipe, old_item, new_item)
    if data.raw.recipe[recipe] and data.raw.recipe[recipe].ingredients then
        replace_ingredient(data.raw.recipe[recipe].ingredients, old_item, new_item)
    end

    if data.raw.recipe[recipe .. "-recycling"] and data.raw.recipe[recipe .. "-recycling"].results then
        replace_results(data.raw.recipe[recipe .. "-recycling"].results, old_item, new_item)
    end
end

update_recipe("concrete", "iron-ore", "iron-stick")

if mods["Dectorio"] then
    update_recipe("dect-concrete-grid", "iron-ore", "iron-stick")
end

-- My code below

local production_and_logistics_items = {}

for name, item in pairs(data.raw["item"]) do
    if item.group and (item.group.name == "logistics" or item.group.name == "production") then
        table.insert(production_and_logistics_items, item)
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

local function calculate_raw_material_cost(ingredient_name, amount)
    if cost_cache[ingredient_name] then
        return cost_cache[ingredient_name] * amount
    end

    if is_raw_material(ingredient_name) then
        cost_cache[ingredient_name] = 1
        return amount
    end

    local recipe = data.raw["recipe"][ingredient_name]

    if not recipe then
        cost_cache[ingredient_name] = 1
        return amount
    end

    local total_cost = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local ingredient_amount = (ingredient.amount or (ingredient.amount_min + ingredient.amount_max) / 2) or 1
        total_cost = total_cost + calculate_raw_material_cost(ingredient.name, ingredient_amount)
    end

    local output_amount = 1
    if recipe.result_count then
        output_amount = recipe.result_count
    elseif recipe.results and recipe.results[1] and recipe.results[1].amount then
        output_amount = recipe.results[1].amount
    end

    total_cost = total_cost / output_amount

    cost_cache[ingredient_name] = total_cost
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

    if recipe and recipe.ingredients then
        local winner = get_most_complex_ingredient(recipe)
        
        if winner then
            local total_raw_cost = calculate_total_raw_cost(recipe)
            local winner_raw_cost = calculate_raw_material_cost(winner.name, 1)
            local scaling_factor = total_raw_cost / winner_raw_cost
            local scaled_quantity = math.ceil(scaling_factor)

            modify_recipe(recipe, winner, scaled_quantity)
        end
    end
end