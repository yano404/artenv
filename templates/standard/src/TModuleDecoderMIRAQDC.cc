/*
 * @file TModuleDecoderMIRAQDC.cc
 * @date  Created : 2024.05.17 (T.Yano)
 *  Last Modified : 2024.05.17 (T.Yano)
 */
#include "TModuleDecoderMIRAQDC.h"
#include <TRawDataTimingCharge.h>
#include <TObjArray.h>

using art::TModuleDecoderMIRAQDC;
using art::TRawDataTimingCharge;

typedef TRawDataTimingCharge MIRAQDCRaw_t;

ClassImp(TModuleDecoderMIRAQDC)

TModuleDecoderMIRAQDC::TModuleDecoderMIRAQDC()
  : TModuleDecoder(kID, MIRAQDCRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderMIRAQDC::TModuleDecoderMIRAQDC(Int_t id)
  : TModuleDecoder(id, MIRAQDCRaw_t::Class()) {
  fHitData = new TObjArray;
}

TModuleDecoderMIRAQDC::~TModuleDecoderMIRAQDC()
{
  if (fHitData) delete fHitData;
  fHitData = NULL;
}

Int_t TModuleDecoderMIRAQDC::Decode(char* buf, const int &size, TObjArray *seg)
{
  UInt_t *evtdata = (UInt_t*) buf;
  UInt_t evtsize = size/sizeof(UInt_t);
  constexpr Int_t igeo = 0;
  
  fHitData->Clear();

  // word 
  //     0 : hit pattern.
  //       : currently hit pattern is fixed to 0xffff_0000.
  //       : so, hit pattern is ignored in this decoder.
  // 3*n+1 : header of ch n; lower 4 bit represents ch(=n).
  // 3*n+2 : integral value of ch n.
  // 3*n+3 : numerator to calculate centroid timing of ch n.
 
  for(size_t i{1}; i != evtsize; i += 3) {
    Int_t  ch = (evtdata[i] & 0x0000000f); // channel
    UInt_t q  = evtdata[i+1]; // integral value
    UInt_t tn = evtdata[i+2]; // numerator to calculate cenntroid timing

    Double_t tm = (Double_t)tn / q;

    if (fHitData->GetEntriesFast() <= ch || !fHitData->At(ch)) {
      // if no data object is available, create one
      auto obj = static_cast<MIRAQDCRaw_t*>(this->New());
      obj->SetSegInfo(seg->GetUniqueID(), igeo, ch);
      fHitData->AddAtAndExpand(obj, ch);
      seg->Add(obj);
    }

    auto data = static_cast<MIRAQDCRaw_t*>(fHitData->At(ch));
    data->SetTiming(tm);
    data->SetCharge(q);
    fHitData->AddAt(NULL,ch);
  }

  return 0;
}
