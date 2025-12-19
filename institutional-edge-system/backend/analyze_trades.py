"""
Analyze backtest trades to identify patterns
"""
import pandas as pd
import numpy as np

# Load data
df = pd.read_csv('reports/backtest_EURUSD_H1_trades.csv')

print('='*70)
print('ANÁLISIS DETALLADO DEL TRADING ENGINE')
print('='*70)
print()

# 1. Performance por Confluence Score
print('1. PERFORMANCE POR CONFLUENCE SCORE:')
print('-'*70)
for score in sorted(df['confluence_score'].unique()):
    subset = df[df['confluence_score'] == score]
    win_rate = (subset['pnl'] > 0).sum() / len(subset) * 100
    avg_pnl = subset['pnl'].mean()
    avg_r = subset['return_r'].mean()
    print(f'Score {score:2d}: {len(subset):3d} trades | WR: {win_rate:5.1f}% | Avg PnL: ${avg_pnl:7.2f} | Avg R: {avg_r:5.2f}')

print()

# 2. Performance BUY vs SELL
print('2. PERFORMANCE BUY vs SELL:')
print('-'*70)
for trade_type in ['BUY', 'SELL']:
    subset = df[df['type'] == trade_type]
    win_rate = (subset['pnl'] > 0).sum() / len(subset) * 100
    avg_pnl = subset['pnl'].mean()
    avg_r = subset['return_r'].mean()
    print(f'{trade_type:4s}: {len(subset):3d} trades | WR: {win_rate:5.1f}% | Avg PnL: ${avg_pnl:7.2f} | Avg R: {avg_r:5.2f}')

print()

# 3. Exit Reasons
print('3. EXIT REASONS (TP vs SL):')
print('-'*70)
for reason in ['TP', 'SL']:
    subset = df[df['exit_reason'] == reason]
    avg_pnl = subset['pnl'].mean()
    avg_r = subset['return_r'].mean()
    count = len(subset)
    pct = count / len(df) * 100
    print(f'{reason:2s}: {count:3d} trades ({pct:5.1f}%) | Avg PnL: ${avg_pnl:7.2f} | Avg R: {avg_r:5.2f}')

print()

# 4. Winners vs Losers
print('4. WINNERS vs LOSERS:')
print('-'*70)
winners = df[df['pnl'] > 0]
losers = df[df['pnl'] < 0]
print(f'Winners: {len(winners):3d} | Avg: ${winners["pnl"].mean():7.2f} | Avg R: {winners["return_r"].mean():5.2f}')
print(f'Losers:  {len(losers):3d} | Avg: ${losers["pnl"].mean():7.2f} | Avg R: {losers["return_r"].mean():5.2f}')

print()

# 5. Análisis de Stop Loss
print('5. ANÁLISIS DE STOP LOSS:')
print('-'*70)
sl_trades = df[df['exit_reason'] == 'SL']
sl_r_values = sl_trades['return_r']
print(f'Total SL hits: {len(sl_trades)}')
print(f'Promedio R en SL: {sl_r_values.mean():.2f}')
print(f'Std Dev R en SL: {sl_r_values.std():.2f}')
print(f'Min R en SL: {sl_r_values.min():.2f}')
print(f'Max R en SL: {sl_r_values.max():.2f}')

print()

# 6. Análisis de Take Profit
print('6. ANÁLISIS DE TAKE PROFIT:')
print('-'*70)
tp_trades = df[df['exit_reason'] == 'TP']
tp_r_values = tp_trades['return_r']
print(f'Total TP hits: {len(tp_trades)}')
print(f'Promedio R en TP: {tp_r_values.mean():.2f}')
print(f'Std Dev R en TP: {tp_r_values.std():.2f}')
print(f'Min R en TP: {tp_r_values.min():.2f}')
print(f'Max R en TP: {tp_r_values.max():.2f}')

print()

# 7. Confluence alta vs baja
print('7. CONFLUENCE ALTA vs BAJA:')
print('-'*70)
high_conf = df[df['confluence_score'] >= 9]
low_conf = df[df['confluence_score'] <= 8]
print(f'Conf 9-11: {len(high_conf):3d} trades | WR: {(high_conf["pnl"]>0).sum()/len(high_conf)*100:5.1f}% | Avg R: {high_conf["return_r"].mean():5.2f}')
print(f'Conf 7-8:  {len(low_conf):3d} trades | WR: {(low_conf["pnl"]>0).sum()/len(low_conf)*100:5.1f}% | Avg R: {low_conf["return_r"].mean():5.2f}')

print()

# 8. Análisis de duración
print('8. DURACIÓN DE TRADES:')
print('-'*70)
print(f'Duración promedio winners: {winners["duration_hours"].mean():.1f} horas')
print(f'Duración promedio losers:  {losers["duration_hours"].mean():.1f} horas')
print(f'Duración promedio TP:      {tp_trades["duration_hours"].mean():.1f} horas')
print(f'Duración promedio SL:      {sl_trades["duration_hours"].mean():.1f} horas')

print()
print('='*70)
print()

# Conclusiones
print('CONCLUSIONES Y RECOMENDACIONES:')
print('-'*70)

# Check if higher confluence is better
if (high_conf["pnl"]>0).sum()/len(high_conf) > (low_conf["pnl"]>0).sum()/len(low_conf):
    print('✅ Señales con confluence 9+ tienen MEJOR win rate → Usar min_confluence=8 o 9')
else:
    print('⚠️  No hay diferencia significativa por confluence → Problema en la lógica')

# Check TP vs SL balance
tp_count = len(tp_trades)
sl_count = len(sl_trades)
if tp_count < sl_count:
    print(f'⚠️  Más SL ({sl_count}) que TP ({tp_count}) → TPs muy lejos o SLs muy cerca')
else:
    print(f'✅ Balance razonable: {tp_count} TP vs {sl_count} SL')

# Check R:R
avg_tp_r = tp_r_values.mean()
if avg_tp_r < 1.5:
    print(f'⚠️  TP promedio {avg_tp_r:.2f}R es bajo → Necesitas usar TP2 o TP3')
else:
    print(f'✅ TP promedio {avg_tp_r:.2f}R es razonable')

# Check BUY vs SELL
buy_wr = (df[df['type']=='BUY']['pnl']>0).sum() / len(df[df['type']=='BUY']) * 100
sell_wr = (df[df['type']=='SELL']['pnl']>0).sum() / len(df[df['type']=='SELL']) * 100
if abs(buy_wr - sell_wr) > 10:
    better = 'BUY' if buy_wr > sell_wr else 'SELL'
    print(f'⚠️  {better} tiene significativamente mejor WR → Considerar solo {better}')
else:
    print('✅ BUY y SELL tienen performance similar')

print()
print('='*70)
