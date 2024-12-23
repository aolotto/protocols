AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"

Unburned = Unburned or 0

Handlers.add("info","Info",function(msg)
  msg.reply({
    Agent = AGENT
  })
end)

Handlers.burn = function(cost,quantity)
  Send({
    Action = "Burn",
    Target = AGENT,
    Quantity = tostring(quantity),
    Cost = tostring(cost)
  }).onReply(function (msg)
    Unburned = Unburned - tonumber(quantity)
  end)
end