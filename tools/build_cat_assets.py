# -*- coding: utf-8 -*-
"""
把「敲钉子的猫」单张插画拆成可动画的两层：

  assets/cat-base.png     —— 猫 + 木板（实心纸色，挡住背后元素）+ 不含锤子
  assets/cat-hammer.png   —— 锤子（内部纸色实心），绕握把旋转即可敲击

用法：python tools/build_cat_assets.py
换图时改 SRC / PIVOT / 锤子种子点即可。
"""
import os
from collections import deque

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "敲钉子的猫.png")
OUT = os.path.join(ROOT, "assets")
PAPER = np.array([247, 244, 236], np.uint8)   # 与页面纸色一致
INK = np.array([18, 23, 47], np.uint8)        # 与页面墨色一致

# 锤子在图片里的握把位置（左爪内部），旋转轴
PIVOT = (520, 1040)
GRIP_R = 62            # 握把圆盘：这一圈内保留底图，旋转时不会有缺口
SEEDS_HAMMER = [(950, 770), (1010, 620)]   # 锤头内部 / 锤柄内部（y, x）
SEED_BODY = (800, 760)                     # 猫身内部
SEED_BOARD = (1350, 700)                   # 木板内部
WATERMARK = (1400, 1220)                   # 右下角 AI 水印裁掉（y0, x0）


def flood(gray, seed, limit=2_000_000):
    h, w = gray.shape
    ink = gray < 110
    visited = np.zeros((h, w), bool)
    q = deque([seed])
    visited[seed] = True
    pts = []
    while q:
        y, x = q.popleft()
        if ink[y, x]:
            continue
        pts.append((y, x))
        if len(pts) > limit:
            return None
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < h and 0 <= nx < w and not visited[ny, nx] and not ink[ny, nx]:
                visited[ny, nx] = True
                q.append((ny, nx))
    return pts


def main():
    os.makedirs(OUT, exist_ok=True)
    src = Image.open(SRC).convert("RGB")
    gray = np.array(src.convert("L"))
    h, w = gray.shape
    arr = gray.astype(np.float32)

    # 锤子
    hammer = np.zeros((h, w), bool)
    for seed in SEEDS_HAMMER:
        for y, x in flood(gray, seed):
            hammer[y, x] = True
    hammer = np.array(
        Image.fromarray((hammer * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(13))
    ) > 0

    # 实心区域：猫身 + 木板
    solid = np.zeros((h, w), bool)
    for seed in (SEED_BODY, SEED_BOARD):
        pts = flood(gray, seed)
        if pts is None:
            raise SystemExit("flood 失败：轮廓可能有缺口")
        for y, x in pts:
            solid[y, x] = True

    yy, xx = np.mgrid[0:h, 0:w]
    grip = ((xx - PIVOT[0]) ** 2 + (yy - PIVOT[1]) ** 2) < GRIP_R ** 2

    # ---------- 底图 ----------
    clear_hammer = hammer & (~grip)          # 锤子擦掉（握把圆盘保留）
    solid = solid | clear_hammer             # 擦掉的地方用纸色补实，挡住背后圆环
    dark = arr < 160

    rgb = np.zeros((h, w, 3), np.uint8)
    rgb[:, :] = PAPER
    rgb[dark] = INK
    rgb[clear_hammer] = PAPER          # 锤子位置必须是纯纸色，不能留下原来的墨线

    line_alpha = np.clip(255 - arr * 1.02, 0, 255)
    alpha = np.where(solid, 255, line_alpha).astype(np.uint8)
    alpha[WATERMARK[0]:, WATERMARK[1]:] = 0
    # 去掉原图那条横贯整幅的桌子线（改由 canvas 画一条更长的）
    alpha[1224:1268, :] = 0
    rgb[WATERMARK[0]:, WATERMARK[1]:] = PAPER

    base = np.dstack([rgb, alpha])
    Image.fromarray(base, "RGBA").save(os.path.join(OUT, "cat-base.png"))

    # ---------- 锤子层 ----------
    ham_rgb = np.zeros((h, w, 3), np.uint8)
    ham_rgb[:, :] = PAPER
    ham_rgb[dark] = INK
    ham_alpha = np.where(hammer, 255, 0).astype(np.uint8)
    ham_alpha[WATERMARK[0]:, WATERMARK[1]:] = 0
    ham = np.dstack([ham_rgb, ham_alpha])
    Image.fromarray(ham, "RGBA").save(os.path.join(OUT, "cat-hammer.png"))

    print("saved:", base.shape, ham.shape, "pivot", PIVOT)

    # ---------- 哈气的猫（纯线稿，透明底） ----------
    hiss_path = os.path.join(ROOT, "哈气的猫.png")
    if os.path.exists(hiss_path):
        hs = Image.open(hiss_path).convert("RGB")
        hg = np.array(hs.convert("L")).astype(np.float32)
        hrgb = np.zeros(hg.shape + (3,), np.uint8)
        hrgb[:, :] = PAPER
        hrgb[hg < 160] = INK
        halpha = np.clip(255 - hg * 1.02, 0, 255).astype(np.uint8)
        halpha[1390:, 1200:] = 0        # 去掉右下角水印
        Image.fromarray(np.dstack([hrgb, halpha]), "RGBA").save(
            os.path.join(OUT, "cat-hiss.png")
        )

        # 内容包围盒（给前端定位用）
        ys, xs = np.where(halpha > 40)
        print("hiss bbox:", xs.min(), ys.min(), xs.max(), ys.max())


if __name__ == "__main__":
    main()
