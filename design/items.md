# Items and Economy (v1)

> Implemented in `game/scripts/items/items.gd` (rules), `player/player.gd` (bag, equip, loot,
> potions, buy/sell) and `ui/inventory.gd` (the bags window). Based on Oldworld2's
> `design/items.md`, simplified for a first version. Numbers are starting values.

## 1. What exists

- **Bag:** 20 slots (B or I opens the bags window, which doesn't pause the game). Click an item
  to equip it (the old one goes back to the bag), click a potion to drink it, click an equipped
  item to take it off. Hover shows the details.
- **Slots:** Head, Chest, Legs, Hands, Feet, Main hand, Off hand, Neck, Ring.
- **Weapons and shields are visible:** the main hand shows the item's kind (sword, mace, dagger,
  staff, axe), a shield appears on the forearm, and a head item shows as a plate helm,
  chainmail coif, leather cap or cloth hood. Other armor changes the numbers only; the class
  outfit stays (visible body armor needs per-item outfits, later).
- **Healing Potion:** restores 35% health, 60 s cooldown, key R. New heroes start with 3.
- **Money** is counted in bronze and shown WoW style: 100 bronze = 1 silver, 100 silver = 1 gold.

## 2. Rarity and stat budget

| Rarity | Color | Budget | Bonus stats |
|---|---|---:|---|
| Common | white | 1.0× | none |
| Uncommon | green | 1.2× | one suffix stat |
| Rare | blue | 1.45× | both suffix stats |
| Epic | purple | 1.75× | both suffix stats + crit |

`Budget = (1 + 0.1 × (ItemLevel − 1)) × 1.25 × SlotMod × RarityMod`, with SlotMod 1.0 for chest,
legs and main hand, 0.8 head, 0.6 hands, feet and off hand, 0.45 neck and ring. Commons put the
whole budget into the base stat; better items put 45% into the suffix stats. A full set of
greens at the hero's level adds about a third to Attack and Defense. Required level =
ItemLevel − 2.

- **Armor** gives Defense and Resistance by type: cloth 0.5/1.0, leather 0.8/0.6,
  mail 0.95/0.45, plate 1.15/0.3 per budget point. A class wears its own armor type or lighter
  (warrior/paladin plate, hunter/shaman mail, rogue/druid leather, mage/warlock/priest cloth).
- **Weapons** put 2.2× their budget into Attack (or Magic, plus some Mana, for casters' staves,
  maces and daggers): weapon kinds per class as in Oldworld2 (sword, axe, mace, dagger, staff,
  bow). **Off hands:** shield (Defense; warrior, paladin, shaman), orb (Magic; casters),
  parrying dagger (Attack; rogue).
- **Jewelry** (neck, ring): one random stat.
- **Suffixes:** of the Bear (Attack, Health), Owl (Magic, Mana), Fox (Crit, Attack), Turtle
  (Defense, Resistance), Serpent (Magic, Crit), Boar (Attack, Defense), Wolf (Attack, Crit),
  Vigor (Health, Mana). 75% of suffixes fit the class.
- Names: material by item level (Iron/Steel/Mithril plate, Linen/Wool/Silk cloth, …) + noun +
  suffix, e.g. "Iron Gauntlets of the Boar".

## 3. Loot

Auto loot into the bag (a message and a colored floating name):

| Source | Gear | Rarity odds (c/u/r/e) | Potion |
|---|---:|---|---:|
| Trash | 7% | 80 / 18 / 2 / 0 | 12% |
| Elite | 60% | 55 / 35 / 9 / 1 | 30% |

Item level = enemy level; 60% of the gear is made for the hero's class.

**Treasure chests** (3 per zone, `world/chest.gd`): money (10–20 × zone level bronze), 50% a
potion, 70% an item with elite odds at the zone's top level. Opened chests are saved.

## 4. Merchant

Every inn has a merchant: within 24 m of the inn the bags window shows the merchant's goods
(potions, six commons for the class at the hero's level, sometimes an uncommon; restocked on
every visit). Click to buy; right-click a bag item to sell.

- Sell price: `ItemLevel × RarityPrice × SlotMod` bronze, RarityPrice 5/12/30/75.
- Buy price: 4× the sell price; potions 4 + 2 × level bronze.
- Death costs 10% of the money (game-design.md, section 7).

## 5. Later

Visible armor, more slots (shoulders, back, wrist, waist, trinkets, ranged/relic), food,
cures, named rare and epic items, item comparison in the tooltip.
