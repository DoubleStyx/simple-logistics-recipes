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
    local raw_materials = {
        ["item"] = {
            ["iron-plate"] = true,
            ["copper-plate"] = true,
            ["stone-brick"] = true,
            ["steel-plate"] = true,
            ["concrete"] = true,
            ["plastic-bar"] = true,
            ["processing-unit"] = true
        },
        ["fluid"] = {
            ["crude-oil"] = true,
        }
    }
    return raw_materials[ingredient_type] and raw_materials[ingredient_type][ingredient_name] or false
end

local complexity_cache = {}

local function calculate_complexity(ingredient_name, visited)
    visited = visited or {}
    if visited[ingredient_name] then
        return {depth = 0, quantity = 1}
    end
    visited[ingredient_name] = true

    if complexity_cache[ingredient_name] then
        visited[ingredient_name] = nil
        return complexity_cache[ingredient_name]
    end

    if is_raw_material(ingredient_name, "item") or is_raw_material(ingredient_name, "fluid") then
        complexity_cache[ingredient_name] = {depth = 0, quantity = 1}
        visited[ingredient_name] = nil
        return complexity_cache[ingredient_name]
    end

    local recipe = data.raw["recipe"][ingredient_name]

    if not recipe then
        complexity_cache[ingredient_name] = {depth = 0, quantity = 1}
        visited[ingredient_name] = nil
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
    visited[ingredient_name] = nil
    return complexity_cache[ingredient_name]
end

local function get_raw_material_vector(ingredient_name, amount, ingredient_type, visited)
    visited = visited or {}
    if visited[ingredient_name] then
        return {}
    end
    visited[ingredient_name] = true

    if is_raw_material(ingredient_name, ingredient_type) then
        visited[ingredient_name] = nil
        return {[ingredient_name] = amount}
    end

    local recipe = data.raw["recipe"][ingredient_name]

    if not recipe then
        visited[ingredient_name] = nil
        -- Treat as raw material if no recipe exists
        return {[ingredient_name] = amount}
    end

    local total_output_amount = 1
    if recipe.result_count then
        total_output_amount = recipe.result_count
    elseif recipe.results and recipe.results[1] and recipe.results[1].amount then
        total_output_amount = recipe.results[1].amount
    end

    local raw_materials = {}

    for _, ingredient in pairs(recipe.ingredients) do
        local ingredient_amount = ingredient.amount or (ingredient.amount_min + ingredient.amount_max) / 2 or 1
        local ingredient_type = ingredient.type or "item"
        local sub_raw_materials = get_raw_material_vector(ingredient.name, ingredient_amount, ingredient_type, visited)
        for material, qty in pairs(sub_raw_materials) do
            raw_materials[material] = (raw_materials[material] or 0) + qty * amount / total_output_amount
        end
    end

    visited[ingredient_name] = nil
    return raw_materials
end

local function dot_product(vec1, vec2)
    local result = 0
    for key, val in pairs(vec1) do
        if vec2[key] then
            result = result + val * vec2[key]
        end
    end
    return result
end

local function vector_norm_squared(vec)
    local result = 0
    for key, val in pairs(vec) do
        result = result + val * val
    end
    return result
end

local function get_most_complex_ingredient(recipe)
    local winner = nil
    local winner_complexity = nil

    for _, ingredient in pairs(recipe.ingredients) do
        local ingredient_name = ingredient.name or ingredient[1]
        local ingredient_type = ingredient.type or "item"
        local comp = calculate_complexity(ingredient_name)

        if not winner_complexity or 
           comp.depth > winner_complexity.depth or
           (comp.depth == winner_complexity.depth and comp.quantity > winner_complexity.quantity) then
            winner = {name = ingredient_name, type = ingredient_type}
            winner_complexity = comp
        end
    end

    return winner
end

local function modify_recipe(recipe, winner, scaled_quantity)
    recipe.ingredients = {
        {type = winner.type, name = winner.name, amount = scaled_quantity}
    }
end

for _, item in pairs(production_and_logistics_items) do
    local recipe = data.raw["recipe"][item.name]
    if recipe and recipe.ingredients then
        local winner = get_most_complex_ingredient(recipe)
        if winner then
            -- Calculate raw material vector R for the original recipe
            local R = {}
            for _, ingredient in pairs(recipe.ingredients) do
                local amount = (ingredient.amount or (ingredient.amount_min + ingredient.amount_max) / 2) or 1
                local ingredient_type = ingredient.type or "item"
                local ingredient_vector = get_raw_material_vector(ingredient.name, amount, ingredient_type)
                for material, qty in pairs(ingredient_vector) do
                    R[material] = (R[material] or 0) + qty
                end
            end

            -- Calculate raw material vector W for the winner ingredient
            local W = get_raw_material_vector(winner.name, 1, winner.type)

            -- Compute scaling factor s using mean squared error (least squares projection)
            local numerator = dot_product(R, W)
            local denominator = vector_norm_squared(W)
            local s = numerator / denominator

            -- Modify the recipe by replacing ingredients with the winner ingredient scaled by s
            local scaled_quantity = math.ceil(s)
            modify_recipe(recipe, winner, scaled_quantity)
        end
    end
end
