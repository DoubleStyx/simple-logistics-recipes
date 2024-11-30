local simplified_recipes = {}

local recipes = data.raw["recipe"]
for recipe_name, recipe in pairs(recipes) do
    local should_include = true

    local products = recipe.results

    if products then
        for _, product in pairs(products) do
            local product_name = product.name
            log("Product name: " .. product_name)
            local product_type = product.type
            if product_type == "item" then
                local item = data.raw["item"][product_name]
                if item then
                    local subgroup_name = item.subgroup
                    if subgroup_name then
                        local subgroup = data.raw["item-subgroup"][subgroup_name]
                        if subgroup then
                            local group_name = subgroup.group
                            if group_name == "intermediate-products" then
                                should_include = false
                                log("Excluded product.")
                                break
                            end
                        end
                    end
                end
            end
        end
    end

    if should_include then
        simplified_recipes[recipe_name] = recipe
    end
end

local function is_raw_material(ingredient_name, ingredient_type)
    return not data.raw["recipe"][ingredient_name]
end

local function calculate_total_raw_cost(item_name, item_type, visited)
    visited = visited or {}
    local key = item_type .. ":" .. item_name
    if visited[key] then
        return 0
    end
    visited[key] = true

    if is_raw_material(item_name, item_type) then
        local weight = (item_type == "fluid" and settings.startup["fluid-unit-weight"].value) or settings.startup["item-unit-weight"].value
        visited[key] = nil
        return weight
    end

    local recipe = data.raw["recipe"][item_name]
    if not recipe or not recipe.ingredients then
        local weight = (item_type == "fluid" and settings.startup["fluid-unit-weight"].value) or settings.startup["item-unit-weight"].value
        visited[key] = nil
        return weight
    end

    local total_raw_input = 0

    for _, ingredient in pairs(recipe.ingredients) do
        local ing_type = ingredient.type or "item"
        local amount = ingredient.amount
            or (ingredient.amount_min + ingredient.amount_max) / 2
            or 1
        local ing_name = ingredient.name or ingredient[1]
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
        local ing_type = ingredient.type or "item"
        if ing_type == "item" then
            local ing_name = ingredient.name or ingredient[1]
            local raw_cost = calculate_total_raw_cost(ing_name, ing_type)
    
            if raw_cost > highest_raw_cost then
                highest_raw_cost = raw_cost
                selected_ingredient = {name = ing_name, type = ing_type, raw_cost = raw_cost}
            end
        end
    end

    return selected_ingredient
end

local function modify_recipe(recipe, winner, total_item_raw_cost)
    local total_output = 1
    if recipe.results then
        total_output = recipe.results[1].amount
    end

    local scale = (total_item_raw_cost / winner.raw_cost) * total_output
    local scaled_quantity = (settings.startup["round-down"].value and math.floor(scale)) or math.ceil(scale)

    scaled_quantity = math.max(1, scaled_quantity)
    local max_value = 65535
    scaled_quantity = math.min(scaled_quantity, max_value)

    recipe.ingredients = {
        {type = winner.type, name = winner.name, amount = scaled_quantity}
    }
end


for recipe_name, recipe in pairs(simplified_recipes) do
    if recipe and recipe.ingredients then
        local total_item_raw_cost = calculate_total_raw_cost(recipe_name, "item")

        local winner = get_most_expensive_ingredient(recipe)
        if winner then
            modify_recipe(recipe, winner, total_item_raw_cost)
        end
    end
end
