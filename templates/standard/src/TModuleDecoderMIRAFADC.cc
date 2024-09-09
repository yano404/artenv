/*
 * @file TModuleDecoderMIRAFADC.cc
 * @date  Created : 2024.03.06 KWS
 *  Last Modified : 2024.09.09 T.Yano
 *--------------------------------------------------------
 *    Comment : MIRA FADC decoder for ridf format 
 *              original : TArtDecoderMIRAFADC.cc by H. Baba
 *
 *--------------------------------------------------------
 *    Copyright (C) by Shoichiro KAWASE
 */
#include "TModuleDecoderMIRAFADC.h"
#include <TRawDataTimingCharge.h>
#include <TObjArray.h>

using art::TModuleDecoderMIRAFADC;
using art::TRawDataTimingCharge;

typedef TRawDataTimingCharge MIRAFADCRaw_t;

ClassImp(TModuleDecoderMIRAFADC)

TModuleDecoderMIRAFADC::TModuleDecoderMIRAFADC()
  : TModuleDecoder(kID, MIRAFADCRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderMIRAFADC::TModuleDecoderMIRAFADC(Int_t id)
  : TModuleDecoder(id, MIRAFADCRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderMIRAFADC::~TModuleDecoderMIRAFADC()
{
  if (fHitData) delete fHitData;
  fHitData = NULL;
}

Int_t TModuleDecoderMIRAFADC::Decode(char* buf, const int &size, TObjArray *seg)
{
  UInt_t *evtdata = (UInt_t*) buf;
  UInt_t evtsize = size/sizeof(UInt_t);
  constexpr Int_t igeo = 0;
  
  fHitData->Clear();

  for(size_t i{}; i != evtsize; i += 3) {
    Int_t    ch = (evtdata[i]   & 0x0000000f);
    Bool_t   ut = (evtdata[i]   & 0x00004000) >> 14; // under threshold
    Bool_t   ht = (evtdata[i]   & 0x00008000) >> 15; // hit
    UShort_t tt = (evtdata[i]   & 0xffff0000) >> 16; // time
    UInt_t   tn = (evtdata[i+1] & 0x0003ffff);       // time numerator
    UShort_t td = (evtdata[i+1] & 0xfffc0000) >> 18; // time denominator
    Short_t  bs = (evtdata[i+2] & 0xffff0000) >> 16; // baseline
    Short_t  tp = (evtdata[i+2] & 0x0000ffff);       // trapezoid peak

    if(ht && !ut) {
      Int_t peak = (Int_t)tp - bs;
      Double_t tm = tt - (Double_t)tn / td;

      if (fHitData->GetEntriesFast() <= ch || !fHitData->At(ch)) {
	// if no data object is available, create one
	auto obj = static_cast<MIRAFADCRaw_t*>(this->New());
	obj->SetSegInfo(seg->GetUniqueID(), igeo, ch);
	fHitData->AddAtAndExpand(obj, ch);
	seg->Add(obj);
      }

      // printf("%u %d %d %d %hu %hu %hu %hd %hd\n",seg->GetUniqueID(),ch,ut,ht,tt,tn,td,bs,tp);
      // printf("%u %d %lf %d\n",seg->GetUniqueID(),ch,tm,peak);

      auto data = static_cast<MIRAFADCRaw_t*>(fHitData->At(ch));
      data->SetTiming(tm);
      data->SetCharge(peak);
      fHitData->AddAt(NULL,ch);
    }
  }

  return 0;
}
