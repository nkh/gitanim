/*
 * ad_layer_indent_last.c — standalone: move indent deletes + adjust positions
 *
 * Moves leading whitespace DELETE ops to end of line segment.
 * Adjusts content ops' col by +n_indent (indent still in buffer
 * when content runs first). Indent deletes stay at col 1.
 * Passes through all other positions unchanged (from ad_layer_reorder).
 */
#include "ad_layer_common.h"
int main(void) {
    char line[PP_MAX_LINE];
    Op *ops=NULL;int n_ops=0,ops_cap=0,in_hunk=0;Hunk hunk={0};
    ops_cap=4096;ops=(Op *)malloc(ops_cap*sizeof(Op));
    while(fgets(line,sizeof(line),stdin)){
        line[strcspn(line,"\n\r")]=0;if(line[0]==0)continue;
        if(line[0]=='#'){if(strstr(line,"raw diff")||strstr(line,"post-processed"))printf("# diffvim post-processed v2\n");else printf("%s\n",line);continue;}
        if(strncmp(line,"HUNK\t",5)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0,seg_start=0;
                for(int i=0;i<=n_ops;i++){
                    int is_b=(i==n_ops);
                    if(i<n_ops&&i>seg_start){if(ops[i].code==10&&!pp_is_debug_op(&ops[i]))is_b=1;if(!pp_is_debug_op(&ops[i])&&!pp_is_debug_op(&ops[i-1])){if(ops[i].line!=ops[i-1].line)is_b=1;}}
                    if(is_b){
                        int sl=i-seg_start;
                        if(sl>0){
                            int ie=seg_start;
                            for(int j=seg_start;j<i;j++){if(pp_is_debug_op(&ops[j]))continue;if(strcmp(ops[j].type,"delete")==0&&(ops[j].code==32||ops[j].code==9))ie=j+1;else break;}
                            int ni=ie-seg_start;
                            if(ni==0){
                                for(int j=seg_start;j<i;j++)out[n_out++]=ops[j];
                            }else{
                                int nl=-1;
                                for(int j=i-1;j>=ie;j--){if(!pp_is_debug_op(&ops[j])&&ops[j].code==10){nl=j;break;}}
                                int ce=(nl>=0)?nl:i;
                                /* Content ops: adjust col by +n_indent */
                                for(int j=ie;j<ce;j++){
                                    out[n_out]=ops[j];
                                    out[n_out].col=ops[j].col+ni;
                                    n_out++;
                                }
                                /* Indent deletes: keep at col 1 */
                                for(int j=seg_start;j<ie;j++){
                                    out[n_out]=ops[j];
                                    out[n_out].col=1;
                                    n_out++;
                                }
                                /* \n op: keep as-is */
                                if(nl>=0)out[n_out++]=ops[nl];
                            }
                        }
                        seg_start=i;
                    }
                }
                pp_write_hunk(&hunk);
                for(int i=0;i<n_out;i++)pp_write_op(&out[i]);
                pp_write_hunk_end();
                free(out);
            }
            sscanf(line,"HUNK\t%d\t%d\t%d\t%d\t%d",&hunk.target,&hunk.del,&hunk.ins,&hunk.end_ins,&hunk.end_del);
            in_hunk=1;n_ops=0;continue;
        }
        if(strncmp(line,"HUNK_END",8)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0,seg_start=0;
                for(int i=0;i<=n_ops;i++){
                    int is_b=(i==n_ops);
                    if(i<n_ops&&i>seg_start){if(ops[i].code==10&&!pp_is_debug_op(&ops[i]))is_b=1;if(!pp_is_debug_op(&ops[i])&&!pp_is_debug_op(&ops[i-1])){if(ops[i].line!=ops[i-1].line)is_b=1;}}
                    if(is_b){int sl=i-seg_start;if(sl>0){int ie=seg_start;for(int j=seg_start;j<i;j++){if(pp_is_debug_op(&ops[j]))continue;if(strcmp(ops[j].type,"delete")==0&&(ops[j].code==32||ops[j].code==9))ie=j+1;else break;}int ni=ie-seg_start;if(ni==0){for(int j=seg_start;j<i;j++)out[n_out++]=ops[j];}else{int nl=-1;for(int j=i-1;j>=ie;j--){if(!pp_is_debug_op(&ops[j])&&ops[j].code==10){nl=j;break;}}int ce=(nl>=0)?nl:i;for(int j=ie;j<ce;j++){out[n_out]=ops[j];out[n_out].col=ops[j].col+ni;n_out++;}for(int j=seg_start;j<ie;j++){out[n_out]=ops[j];out[n_out].col=1;n_out++;}if(nl>=0)out[n_out++]=ops[nl];}}seg_start=i;}
                }
                pp_write_hunk(&hunk);
                for(int i=0;i<n_out;i++)pp_write_op(&out[i]);
                pp_write_hunk_end();
                free(out);
            }
            in_hunk=0;n_ops=0;continue;
        }
        if(in_hunk){if(n_ops>=ops_cap){ops_cap*=2;ops=(Op *)realloc(ops,ops_cap*sizeof(Op));}pp_parse_op(line,&ops[n_ops]);n_ops++;}
    }
    if(in_hunk&&n_ops>0){
        Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0,seg_start=0;
        for(int i=0;i<=n_ops;i++){int is_b=(i==n_ops);if(i<n_ops&&i>seg_start){if(ops[i].code==10&&!pp_is_debug_op(&ops[i]))is_b=1;if(!pp_is_debug_op(&ops[i])&&!pp_is_debug_op(&ops[i-1])){if(ops[i].line!=ops[i-1].line)is_b=1;}}if(is_b){int sl=i-seg_start;if(sl>0){int ie=seg_start;for(int j=seg_start;j<i;j++){if(pp_is_debug_op(&ops[j]))continue;if(strcmp(ops[j].type,"delete")==0&&(ops[j].code==32||ops[j].code==9))ie=j+1;else break;}int ni=ie-seg_start;if(ni==0){for(int j=seg_start;j<i;j++)out[n_out++]=ops[j];}else{int nl=-1;for(int j=i-1;j>=ie;j--){if(!pp_is_debug_op(&ops[j])&&ops[j].code==10){nl=j;break;}}int ce=(nl>=0)?nl:i;for(int j=ie;j<ce;j++){out[n_out]=ops[j];out[n_out].col=ops[j].col+ni;n_out++;}for(int j=seg_start;j<ie;j++){out[n_out]=ops[j];out[n_out].col=1;n_out++;}if(nl>=0)out[n_out++]=ops[nl];}}seg_start=i;}}
        pp_write_hunk(&hunk);
        for(int i=0;i<n_out;i++)pp_write_op(&out[i]);
        pp_write_hunk_end();
        free(out);
    }
    printf("\n");free(ops);return 0;
}
