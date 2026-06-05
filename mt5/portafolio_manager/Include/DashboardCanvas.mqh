//+------------------------------------------------------------------+
//|                                              DashboardCanvas.mqh |
//|                                  Copyright 2026, Portfolio Governor   |
//|                                     https://www.mql5.com              |
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
   CDashboardCanvas() : m_dashWidth(550), m_dashHeight(350), m_fontSize(10), m_rowHeight(20)
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
      TextOut(10, 8, "INFERNAL PORTFOLIO GOVERNOR v1.0", m_colText);
      
      // 3. Draw Health Stats
      TextOut(10, 40, "Equity: $" + DoubleToString(equity, 2), m_colText);
      
      uint ddColor = (dd < 3.0) ? m_colGreen : m_colRed;
      TextOut(200, 40, "DD: " + DoubleToString(dd, 2) + "%", ddColor);
      
      // 4. Draw Ranking Table Header
      int y = 70;
      FillRectangle(0, y, m_dashWidth, y+20, m_colHeader);
      TextOut(10, y+3, "#   Symbol     Score   Req    Dir   Time    Status", m_colText);
      y += 25;
      
      // 5. Draw Ranks
      SymbolRank ranks[];
      int count = manager.GetRanks(ranks);
      
      for(int i=0; i<MathMin(count, 12); i++)
      {
         string rankStr = IntegerToString(ranks[i].rank);
         string symStr  = ranks[i].symbol;
         
         // Score Display: "22.5" or "22.5 (18.0)"
         string scoreStr = DoubleToString(ranks[i].score, 1);
         if(ranks[i].score - ranks[i].adjScore > 0.1)
         {
            scoreStr += " (" + DoubleToString(ranks[i].adjScore, 1) + ")";
         }
         
         string reqStr   = DoubleToString(ranks[i].reqScore, 1);
         
         // Timer Logic
         long rem = ranks[i].timeRemaining;
         string timeStr = StringFormat("%02d:%02d", rem/60, rem%60);
         uint timeCol = m_colText;
         if(rem < 60) timeCol = m_colYellow;
         if(rem < 10) timeCol = m_colRed;
         
         // Direction Icon
         string dirStr = (ranks[i].direction > 0) ? "UP" : "DN"; // Fallback text
         uint dirColor = (ranks[i].direction > 0) ? m_colGreen : m_colRed;
         
         // Status Logic
         bool isHighEnough = (ranks[i].score >= ranks[i].reqScore);
         bool isRanked     = (ranks[i].rank <= 3);
         bool isKZ         = ranks[i].isKZOpen;
         
         string statusStr = "WAIT";
         uint statusCol   = m_colYellow;
         
         if(isHighEnough && isRanked && isKZ) { statusStr = "ACTIVE"; statusCol = m_colGreen; }
         else if(!isKZ)                       { statusStr = "KZ WAIT"; statusCol = ColorToARGB(clrOrange); }
         else if(!isHighEnough)               { statusStr = "LOW SCORE"; statusCol = ColorToARGB(clrGray); }
         else if(!isRanked)                   { statusStr = "RANK QUEUE"; statusCol = m_colYellow; }

         // Columns
         TextOut(10, y, rankStr, m_colText);
         TextOut(40, y, symStr, m_colText);
         
         uint scoreCol = isHighEnough ? m_colGreen : ColorToARGB(clrGray);
         TextOut(120, y, scoreStr, scoreCol);
         TextOut(180, y, reqStr, m_colText);
         TextOut(240, y, dirStr, dirColor);
         TextOut(290, y, timeStr, timeCol);
         TextOut(350, y, statusStr, statusCol);
         
         y += m_rowHeight;
      }
      
      Update(); // Render to chart (CCanvas::Update)
   }
};

#endif
