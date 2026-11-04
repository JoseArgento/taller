# Taller

Para los que craftean en **WoW Forever**. Pineás recetas, ponés cuántas querés hacer, y Taller te dice cuántos materiales necesitás y cuántos tenés: en las bolsas, en el banco y en tus otros personajes. Todo dividido por profesión.

[Read in English](README.en.md)

## Cómo se usa

- **Pinear:** en la ventana de profesiones del juego, tildá la casilla para seguir la receta. Aparece sola en Taller. Si la destildás, se despinea; si la despineás en Taller, se destilda.
- **Cantidad:** `+` y `-` en cada receta (con Shift, de a 10). La cantidad es de **objetos**: si una receta da 5 piedras por crafteo y querés 12, cuenta 3 crafteos.
- **Materiales:** debajo de cada receta, cada material con "tenés / necesitás" y cuántos faltan. Pasando el mouse ves dónde están ("5 Josecito (bolsas), 12 Ana (banco), 3 banco de cuenta").
- **Lista de compras:** la otra pestaña suma todo lo que piden tus recetas, con lo que más falta arriba. Si un material lo hace otra receta tuya (el paño para la camisa), te lo marca.
- **Al craftear** baja la cantidad sola. Cuando llega a cero, te avisa y la saca.
- **En el tooltip** de un material: "Taller: necesitás 20, tenés 3 acá y 12 en Ana".
- `/taller` abre la ventana, `/taller compras` va directo a la lista de compras.

Las recetas son de quien las sabe hacer: si pineás algo con tu alt herrero, lo ves desde cualquier personaje ("la hace Ana").

## Qué cuenta

- **Bolsas** (incluida la bolsa de reagentes): siempre, cada vez que cambian.
- **Banco:** lo que viste la última vez que lo abriste. Si nunca lo abriste con ese personaje, te lo dice.
- **Banco de cuenta:** igual, una sola vez para todos.
- **Otros personajes:** lo que tenían la última vez que entraste con ellos.
- **No cuenta** el correo ni lo que está en la subasta.

## Instalar

Copiá la carpeta `Taller` a `Interface\AddOns\`, dentro de la carpeta de Forever del juego. Entrá una vez con cada personaje (y abrí su banco) para que cuente lo que tiene.

## ¿Por qué otro más?

Ya hay addons de profesiones para Forever, y algunos están muy buenos. *Forever Profession Master* tiene cola con cantidades pero cuenta solo las bolsas. *ItemWatch & Shopping List* suma bolsas y banco pero no tus otros personajes. *ForeverArtisan* cuenta otros personajes si le sumás un addon de bolsas. Taller hace una sola cosa: lo que querés craftear contra todo lo que tenés, en todos tus personajes, sin depender de nada más.

## Cómo se probó

**Probado:**
- ✅ Cada función, evento, template y sonido existe en Forever 1.60.1: `tools/check_api.py` contra los dumps de [Ketho/BlizzardInterfaceResources](https://github.com/Ketho/BlizzardInterfaceResources) y la UI de [Gethe/wow-ui-source](https://github.com/Gethe/wow-ui-source), rama `forever`. Forever usa la API de profesiones moderna (`C_TradeSkillUI.GetRecipeSchematic`, `TRACKED_RECIPE_UPDATE`) y el banco por pestañas (`Enum.BagIndex.CharacterBankTab_*`, `AccountBankTab_*`).
- ✅ [forever-lint](https://github.com/JoseArgento/forever-lint) sin problemas; [Addon Sentry](https://github.com/JoseArgento/addon-sentry): "Sin señales de riesgo".
- ✅ **24 tests** en Lua 5.1 (el Lua de WoW), con varios personajes de la misma cuenta compartiendo los datos guardados.

**Sin probar ⏳** (no tengo el cliente de Forever):
- Cómo se ve la ventana.
- Que la casilla para seguir recetas de Forever dispare `TRACKED_RECIPE_UPDATE` como en retail.
- Que el banco de Forever use las pestañas de banco modernas y que el de cuenta exista.
- Que `UNIT_SPELLCAST_SUCCEEDED` traiga el ID de la receta al craftear (así es en retail).

## Desarrollo

```bash
pip install pytest lupa
pytest
python tools/check_api.py --bir ../BlizzardInterfaceResources --ui ../wow-ui-source --scanner ../addon-sentry/src
```

Un tag `v*` empaqueta el addon con el packager de BigWigs.

Sin relación con Blizzard Entertainment. World of Warcraft es marca registrada de Blizzard Entertainment, Inc. Licencia MIT.
