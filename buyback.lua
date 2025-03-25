AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"
DEFAULT_PAY_TOKEN_ID = DEFAULT_PAY_TOKEN_ID or "<DEFAULT_PAY_TOKEN_ID>"

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

Handlers.requestFunds = function (amount)
  Handlers.once({
    From = DEFAULT_PAY_TOKEN_ID
  })

  Send({
    Action = "Request-Buybacks-Funds",
    Target = AGENT,
    Quantity = amount and string.format("0.f%",amount)
  })
end



