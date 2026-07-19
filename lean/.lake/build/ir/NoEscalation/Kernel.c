// Lean compiler output
// Module: NoEscalation.Kernel
// Imports: public import Init public meta import Init
#include <lean/lean.h>
#if defined(__clang__)
#pragma clang diagnostic ignored "-Wunused-parameter"
#pragma clang diagnostic ignored "-Wunused-label"
#elif defined(__GNUC__) && !defined(__CLANG__)
#pragma GCC diagnostic ignored "-Wunused-parameter"
#pragma GCC diagnostic ignored "-Wunused-label"
#pragma GCC diagnostic ignored "-Wunused-but-set-variable"
#endif
#ifdef __cplusplus
extern "C" {
#endif
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg(lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg___boxed(lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___boxed(lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim___boxed(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_root_elim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_root_elim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_hop_elim___redArg(lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_hop_elim(lean_object*, lean_object*, lean_object*, lean_object*, lean_object*, lean_object*);
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg(lean_object* v_x_1_){
_start:
{
if (lean_obj_tag(v_x_1_) == 0)
{
lean_object* v___x_2_; 
v___x_2_ = lean_unsigned_to_nat(0u);
return v___x_2_;
}
else
{
lean_object* v___x_3_; 
v___x_3_ = lean_unsigned_to_nat(1u);
return v___x_3_;
}
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg___boxed(lean_object* v_x_4_){
_start:
{
lean_object* v_res_5_; 
v_res_5_ = lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg(v_x_4_);
lean_dec_ref(v_x_4_);
return v_res_5_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx(lean_object* v_E_6_, lean_object* v_Comp_7_, lean_object* v_x_8_){
_start:
{
lean_object* v___x_9_; 
v___x_9_ = lp_NoEscalation_NoEscalation_Ctx_ctorIdx___redArg(v_x_8_);
return v___x_9_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorIdx___boxed(lean_object* v_E_10_, lean_object* v_Comp_11_, lean_object* v_x_12_){
_start:
{
lean_object* v_res_13_; 
v_res_13_ = lp_NoEscalation_NoEscalation_Ctx_ctorIdx(v_E_10_, v_Comp_11_, v_x_12_);
lean_dec_ref(v_x_12_);
return v_res_13_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(lean_object* v_t_14_, lean_object* v_k_15_){
_start:
{
if (lean_obj_tag(v_t_14_) == 0)
{
lean_object* v_extender_16_; lean_object* v___x_17_; 
v_extender_16_ = lean_ctor_get(v_t_14_, 0);
lean_inc(v_extender_16_);
lean_dec_ref_known(v_t_14_, 1);
v___x_17_ = lean_apply_2(v_k_15_, v_extender_16_, lean_box(0));
return v___x_17_;
}
else
{
lean_object* v_parent_18_; lean_object* v_extender_19_; lean_object* v___x_20_; 
v_parent_18_ = lean_ctor_get(v_t_14_, 0);
lean_inc_ref(v_parent_18_);
v_extender_19_ = lean_ctor_get(v_t_14_, 1);
lean_inc(v_extender_19_);
lean_dec_ref_known(v_t_14_, 2);
v___x_20_ = lean_apply_3(v_k_15_, v_parent_18_, v_extender_19_, lean_box(0));
return v___x_20_;
}
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim(lean_object* v_E_21_, lean_object* v_Comp_22_, lean_object* v_motive_23_, lean_object* v_ctorIdx_24_, lean_object* v_t_25_, lean_object* v_h_26_, lean_object* v_k_27_){
_start:
{
lean_object* v___x_28_; 
v___x_28_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(v_t_25_, v_k_27_);
return v___x_28_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_ctorElim___boxed(lean_object* v_E_29_, lean_object* v_Comp_30_, lean_object* v_motive_31_, lean_object* v_ctorIdx_32_, lean_object* v_t_33_, lean_object* v_h_34_, lean_object* v_k_35_){
_start:
{
lean_object* v_res_36_; 
v_res_36_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim(v_E_29_, v_Comp_30_, v_motive_31_, v_ctorIdx_32_, v_t_33_, v_h_34_, v_k_35_);
lean_dec(v_ctorIdx_32_);
return v_res_36_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_root_elim___redArg(lean_object* v_t_37_, lean_object* v_root_38_){
_start:
{
lean_object* v___x_39_; 
v___x_39_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(v_t_37_, v_root_38_);
return v___x_39_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_root_elim(lean_object* v_E_40_, lean_object* v_Comp_41_, lean_object* v_motive_42_, lean_object* v_t_43_, lean_object* v_h_44_, lean_object* v_root_45_){
_start:
{
lean_object* v___x_46_; 
v___x_46_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(v_t_43_, v_root_45_);
return v___x_46_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_hop_elim___redArg(lean_object* v_t_47_, lean_object* v_hop_48_){
_start:
{
lean_object* v___x_49_; 
v___x_49_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(v_t_47_, v_hop_48_);
return v___x_49_;
}
}
LEAN_EXPORT lean_object* lp_NoEscalation_NoEscalation_Ctx_hop_elim(lean_object* v_E_50_, lean_object* v_Comp_51_, lean_object* v_motive_52_, lean_object* v_t_53_, lean_object* v_h_54_, lean_object* v_hop_55_){
_start:
{
lean_object* v___x_56_; 
v___x_56_ = lp_NoEscalation_NoEscalation_Ctx_ctorElim___redArg(v_t_53_, v_hop_55_);
return v___x_56_;
}
}
lean_object* initialize_Init(uint8_t builtin);
lean_object* initialize_Init(uint8_t builtin);
static bool _G_initialized = false;
LEAN_EXPORT lean_object* initialize_NoEscalation_NoEscalation_Kernel(uint8_t builtin) {
lean_object * res;
if (_G_initialized) return lean_io_result_mk_ok(lean_box(0));
_G_initialized = true;
res = initialize_Init(builtin);
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
res = initialize_Init(builtin);
if (lean_io_result_is_error(res)) return res;
lean_dec_ref(res);
return lean_io_result_mk_ok(lean_box(0));
}
#ifdef __cplusplus
}
#endif
