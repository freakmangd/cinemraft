return function(m)
    local mod = m:newMod("kiras_silly_stuff")

    local steel_block = mod:addBlock("Steel", {
        texture = "custom_block.png",
        tex_indeces = { 2, 3 },
        mining_time = 4,
        preferred_tool = m.pickaxe,
    })

    mod:setBlockTex(m.dirt, "custom_dirt.png", { 0, 0 })

    mod:addRecipe("Pumpkin Pie", {
        m.pumpkin, m.sugar, m.something,
    })

    mod:addBiome("Jungle", {
        generate = function(x, y, z)
            return steel_block
        end
    })

    m:register(mod)
end
