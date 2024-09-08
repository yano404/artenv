#ifndef LINKDEF_USER_H
#define LINKDEF_USER_H


#ifdef __CINT__

#pragma link off all globals;
#pragma link off all classes;
#pragma link off all functions;

#pragma link C++ class art::TModuleDecoderRICHADCM+;
#pragma link C++ class art::TModuleDecoderMIRAFADC+;
#pragma link C++ class art::TModuleDecoderMIRAQDC+;
#pragma link C++ class art::TModuleDecoderV1730ZLE+;
#pragma link C++ class art::TV1730ZLEDataObject+;
#pragma link C++ class art::TV1730ZLEWaveformData+;

#endif // __CINT__

#endif // LINKDEF_USER_H
