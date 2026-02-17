//+------------------------------------------------------------------+
//|                                              DashboardCanvas.mqh |
//|                                  Copyright 2026, Guido Ambiorix  |
//|                                     https://github.com/GuidoAmbiorix |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_CANVAS_MQH
#define DASHBOARD_CANVAS_MQH

#include <Canvas\Canvas.mqh>
#include "RankManager.mqh"

//+------------------------------------------------------------------+
//| DASHBOARD CANVAS CLASS                                            |
//+------------------------------------------------------------------+
class CDashboardCanvas : public CCanvas
{
private:
   int       m_dashWidth;
   int       m_dashHeight;
   int       m_fontSize;
   int       m_rowHeight;
   
   // Colors
   uint      m_colBg;
   uint      m_colText;
   uint      m_colGreen;
   uint      m_colRed;
   uint      m_colYellow;
   uint      m_colHeader;

public:
   CDashboardCanvas() : m_dashWidth(400), m_dashHeight(300), m_fontSize(10), m_rowHeight(20)
   {
      m_colBg     = ColorToARGB(clrBlack, 220); // Semi-transparent black
      m_colText   = ColorToARGB(clrWhite);
      m_colGreen  = ColorToARGB(clrLime);
      m_colRed    = ColorToARGB(clrRed);
      m_colYellow = ColorToARGB(clrGold);
      m_colHeader = ColorToARGB(clrDimGray);
   }

   //+------------------------------------------------------------------+
   //| Initialize Dashboard                                              |
   //+------------------------------------------------------------------+
   bool Init(string name, int x, int y, int w, int h)
   {
      m_dashWidth = w;
      m_dashHeight = h;
      
      if(!CreateBitmapLabel(name, x, y, w, h, COLOR_FORMAT_ARGB_NORMALIZE))
         return false;
         
      FontSet("Consolas", m_fontSize);
      return true;
   }

   //+------------------------------------------------------------------+
   //| Update Dashboard View                                             |
   //+------------------------------------------------------------------+
   void Render(CRankManager &manager, double equity, double dd, double pf)
   {
      // 1. Clear Background
      Erase(m_colBg);
      FillRectangle(0, 0, m_dashWidth, 30, m_colHeader); // Title Bar
      
      // 2. Draw Title
      TextOut(10, 8, "🧠 PORTFOLIO GOVERNOR v2.0", m_colText);
      
      // 3. Draw Health Stats
      TextOut(10, 40, "Equity: $" + DoubleToString(equity, 2), m_colText);
      
      uint ddColor = (dd < 3.0) ? m_colGreen : m_colRed;
      TextOut(200, 40, "DD: " + DoubleToString(dd, 2) + "%", ddColor);
      
      // 4. Draw Ranking Table Header
      int y = 70;
      FillRectangle(0, y, m_dashWidth, y+20, m_colHeader);
      TextOut(10, y+3, "#   Symbol     Score   Status", m_colText);
      y += 25;
      
      // 5. Draw Ranks
      SymbolRank ranks[];
      int count = manager.GetRanks(ranks);
      
      for(int i=0; i<MathMin(count, 10); i++)
      {
         string rankStr = IntegerToString(ranks[i].rank);
         string symStr  = ranks[i].symbol;
         string scoreStr = DoubleToString(ranks[i].score, 1);
         bool isActive = (ranks[i].rank <= 3);
         string statusStr = isActive ? "ACTIVE" : "WAIT";
         uint statusCol = isActive ? m_colGreen : m_colYellow;
         
         TextOut(10, y, rankStr, m_colText);
         TextOut(40, y, symStr, m_colText);
         TextOut(120, y, scoreStr, m_colText);
         TextOut(190, y, statusStr, statusCol);
         
         y += m_rowHeight;
      }
      
      Update(); // Render to chart (CCanvas::Update)
   }
};

#endif
