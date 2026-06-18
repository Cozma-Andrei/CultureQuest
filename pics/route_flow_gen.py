import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch

fig, ax = plt.subplots(figsize=(9, 3.8))
ax.set_xlim(0, 9)
ax.set_ylim(0, 3.8)
ax.axis('off')

BOX_W, BOX_H = 1.55, 0.62
OVAL_W = BOX_W + 0.15
PURPLE_BG = '#ececff'
PURPLE_BD = '#9370db'

def draw_box(ax, cx, cy, text, shape='rect'):
    if shape == 'oval':
        ax.add_patch(mpatches.Ellipse((cx, cy), OVAL_W, BOX_H,
            facecolor=PURPLE_BG, edgecolor=PURPLE_BD, linewidth=1.3, zorder=3))
    else:
        ax.add_patch(FancyBboxPatch((cx - BOX_W/2, cy - BOX_H/2), BOX_W, BOX_H,
            boxstyle='round,pad=0.04',
            facecolor=PURPLE_BG, edgecolor=PURPLE_BD, linewidth=1.3, zorder=3))
    ax.text(cx, cy, text, ha='center', va='center', fontsize=8.5,
            color='#2d2060', zorder=4, multialignment='center')

def arrow_h(ax, x1, x2, y, label=''):
    """Orizontal: de la centrul x1 la centrul x2 (orice direcție)."""
    going_right = x2 > x1
    src_x = (x1 + BOX_W/2 + 0.04) if going_right else (x1 - BOX_W/2 - 0.04)
    dst_x = (x2 - BOX_W/2 - 0.04) if going_right else (x2 + BOX_W/2 + 0.04)
    ax.annotate('', xy=(dst_x, y), xytext=(src_x, y),
                arrowprops=dict(arrowstyle='->', color='#555', lw=1.3), zorder=2)
    ax.text((x1 + x2) / 2, y + 0.46, label, ha='center', va='center',
            fontsize=7.5, color='#444', multialignment='center', zorder=5)

ROW1, ROW2 = 2.9, 1.0

# ── rând 1 (stânga → dreapta): Start → Obiective → Primii 10 ─────────────
xs1 = [1.1, 3.4, 5.7]
draw_box(ax, xs1[0], ROW1, 'Locație start\npreferințe utilizator', 'oval')
draw_box(ax, xs1[1], ROW1, 'Obiective\ndin apropiere')
draw_box(ax, xs1[2], ROW1, 'Primii 10\ncandidați')
arrow_h(ax, xs1[0], xs1[1], ROW1, '1. obiective în 10 km')
arrow_h(ax, xs1[1], xs1[2], ROW1, '2. FL×0,8 + distanță×0,2')

# ── rând 2 (dreapta → stânga): Traseu → Durate → Rută ───────────────────
# Traseu e direct sub Primii 10 (x=5.7) → săgeata 3 e verticală
xs2 = [5.7, 3.4, 1.1]
draw_box(ax, xs2[0], ROW2, 'Traseu\ninițial')
draw_box(ax, xs2[1], ROW2, 'Durate de\nvizitare scalate')
draw_box(ax, xs2[2], ROW2, 'Rută\nfinală', 'oval')
arrow_h(ax, xs2[0], xs2[1], ROW2, '4. scalare durată după scor FL')
arrow_h(ax, xs2[1], xs2[2], ROW2, '5. construire rută')

# ── săgeată 3: verticală, Primii 10 → Traseu ──────────────────────────────
ax.annotate('',
    xy=(xs1[2], ROW2 + BOX_H/2 + 0.04),
    xytext=(xs1[2], ROW1 - BOX_H/2 - 0.04),
    arrowprops=dict(arrowstyle='->', color='#555', lw=1.3), zorder=2)
ax.text(xs1[2] + 0.20, (ROW1 + ROW2) / 2,
        '3. vecin cel mai\napropiat\n+ departajare interese',
        ha='left', va='center', fontsize=7.5, color='#444',
        multialignment='left', zorder=5)

plt.tight_layout(pad=0.3)
plt.savefig('/home/andrei-cozma/Desktop/Facultate/CultureQuest/pics/route-flow.pdf',
            bbox_inches='tight', dpi=300)
plt.close()
print('OK')
