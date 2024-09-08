/*
 * @file TModuleDecoderRICHADCM.h
 * @date  Created : 2022.07.14 JST
 *  Last Modified : 2022.07.14 JST (HJKT)
 *--------------------------------------------------------
 *    Comment : Si trb decoder for ridf format 
 *              original : TArtDecoderRICHADCM.hh by H. Baba
 *
 *--------------------------------------------------------
 *    Copyright (C) Yuto HIJIAKTA
 */
#ifndef TMODULEDECODERRICHADCM_H
#define TMODULEDECODERRICHADCM_H
#include <TModuleDecoder.h>

namespace art {
  class TModuleDecoderRICHADCM;
}


class art::TModuleDecoderRICHADCM  : public TModuleDecoder {
 public:
  static const int kID = 44;
  enum class EChannelNumberingMode {
				    kOriginal, kH424, kTripE6
  };
  
  TModuleDecoderRICHADCM();         // constructor with default id = kID for compatibility
  TModuleDecoderRICHADCM(Int_t id, EChannelNumberingMode mode = EChannelNumberingMode::kTripE6); // constructor with id
  virtual ~TModuleDecoderRICHADCM();
  virtual Int_t Decode(char* buffer, const int &size, TObjArray *seg);
  virtual Int_t Endian(UInt_t x);

 protected:
  TObjArray *fHitData; // array to temporally store the data for the aggregation
  EChannelNumberingMode fChMode{EChannelNumberingMode::kTripE6};

  ClassDef(TModuleDecoderRICHADCM,0) // decoder for module RICHADCM
};
#endif // end of #ifdef TMODULEDECODERRICHADCM_H
