--[[ The Minebit game list. Adding a game is a row here plus a file in games/,
     which must return a table with run(ctx) that returns the score. ]]

return {
  {
    id = "snake", title = "Snake", module = "games/snake",
    blurb = "Eat, grow, don't bite yourself.", colour = colours.lime,
  },
  {
    id = "blocks", title = "Blocks", module = "games/blocks",
    blurb = "Slide and merge your way to 2048.", colour = colours.orange,
  },
}
