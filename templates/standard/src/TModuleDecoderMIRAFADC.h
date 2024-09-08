/*
 * @file TModuleDecoderMIRAFADC.h
 * @date  Created : 2024.03.06 JST
 *  Last Modified : 2024.03.06 JST (Kawase)
 *--------------------------------------------------------
 *    Comment : MIRA FADC decoder for ridf format 
 *              original : TArtDecoderMIRAFADC.hh by H. Baba
 *
 *--------------------------------------------------------
 *    Copyright (C) Shoichiro KAWASE
 */
#ifndef TMODULEDECODERMIRAFADC_H
#define TMODULEDECODERMIRAFADC_H
#include <TModuleDecoder.h>

namespace art {
  class TModuleDecoderMIRAFADC;
}

class art::TModuleDecoderMIRAFADC  : public TModuleDecoder {
 public:
  static const int kID = 48;

  TModuleDecoderMIRAFADC();
  explicit TModuleDecoderMIRAFADC(Int_t id);
  virtual ~TModuleDecoderMIRAFADC();
  virtual Int_t Decode(char* buffer, const int &size, TObjArray *seg);

 protected:
  TObjArray *fHitData; // array to temporally store the data for the aggregation

 private:
  TModuleDecoderMIRAFADC(const TModuleDecoderMIRAFADC&); // not defined
  TModuleDecoderMIRAFADC& operator=(const TModuleDecoderMIRAFADC&); // not defined
  
  ClassDef(TModuleDecoderMIRAFADC,0) // decoder for module MIRA FADC
};
#endif // end of #ifdef TMODULEDECODERMIRAFADC_H
