AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT_ID>"
DEFAULT_PAY_TOKEN_ID = DEFAULT_PAY_TOKEN_ID or "<PAYTOKEN_ID>"
ALT_WUSDC_POOL = ALT_WUSDC_POOL or "<POOL_ID>"

Unburned = Unburned or 0

-- Handlers.add("info","Info",function(msg)
--   msg.reply({
--     Agent = AGENT
--   })
-- end)

-- Handlers.burn = function(cost,quantity)
--   Send({
--     Action = "Burn",
--     Target = AGENT,
--     Quantity = tostring(quantity),
--     Cost = tostring(cost)
--   }).onReply(function (msg)
--     Unburned = Unburned - tonumber(quantity)
--   end)
-- end

-- Handlers.requestFunds = function (amount)
--   Handlers.once({
--     From = DEFAULT_PAY_TOKEN_ID
--   })

--   Send({
--     Action = "Request-Buybacks-Funds",
--     Target = AGENT,
--     Quantity = amount and string.format("0.f%",amount)
--   })
-- end



-- SWAP = SWAP or {
--   _version = "0.1",
-- }
-- SWAP.getPrice = function (pool)
--   local pool = pool or ALT_WUSDC_POOL or "2sWVPeUTYuB0VMrkgC9m_0MwljaZqEJdAfgJXNZgEIw"
--   Send({
--     Target=pool, Action='Info'
--   }).onReply(function (m)
--     print("DecimalX:"..m.DecimalX)
--     print("DecimalY:"..m.DecimalY)
--     print("X:"..m.X)
--     print("Y:"..m.Y)
--     print("PX:"..m.PX)
--     print("PY:"..m.PY)
--     local xy_price = (m.PX/10^tonumber(m.DecimalX))/(m.PY/10^tonumber(m.DecimalY))
--     print("X:Y Price:"..string.format("%.8f",xy_price))
--     local yx_price = (m.PY/10^tonumber(m.DecimalY))/(m.PX/10^tonumber(m.DecimalX))
--     print("X:Y Price:"..string.format("%.8f",xy_price))
--     print("Y:X Price:"..string.format("%.8f",yx_price))
--   end)
-- end


Handlers.add("bid",{
  Action = "Credit-Notice",
  From = AGENT,
  ['X-Transfer-Type'] = "Bid",
  Qunatity = "%d+",
},function (msg)
  print("Bid Received:"..msg.Qunatity)
end)