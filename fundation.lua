AGENT = AGENT or ao.env.Process.Tags['Agent'] or "<AGENT>"

Handlers.add("info","Info",function(msg)
  msg.reply({
    Agent = AGENT
  })
end)