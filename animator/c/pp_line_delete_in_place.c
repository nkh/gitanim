/*
 * pp_line_delete_in_place.c — standalone: delete lines on their own line
 *
 * When a \n delete would join two lines, and the next line is fully
 * deleted, reorder so content is deleted FIRST (on its own line),
 * then the \n delete joins. Prevents "join then delete" visual.
 *
 * Passes through positions from pp_reorder unchanged.
 */
#include "pp_common.h"

int main(void) {
    char line[PP_MAX_LINE];
    Op *ops=NULL;int n_ops=0,ops_cap=0,in_hunk=0;Hunk hunk={0};
    ops_cap=4096;ops=(Op *)malloc(ops_cap*sizeof(Op));
    while(fgets(line,sizeof(line),stdin)){
        line[strcspn(line,"\n\r")]=0;if(line[0]==0)continue;
        if(line[0]=='#'){if(strstr(line,"raw diff")||strstr(line,"post-processed"))printf("# diffvim post-processed v2\n");else printf("%s\n",line);continue;}
        if(strncmp(line,"HUNK\t",5)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0;
                int i=0;
                while(i<n_ops){
                    /* Check: \n delete on line N, followed by content deletes
                     * on line N+1, followed by \n delete on line N+1 */
                    if(i+2<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code==10&&
                       strcmp(ops[i+1].type,"delete")==0&&ops[i+1].code!=10&&
                       ops[i+1].line==ops[i].line+1){
                        int dl=ops[i].line+1;
                        int cs=i+1,ce=cs;
                        while(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code!=10&&ops[ce].line==dl)ce++;
                        if(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code==10&&ops[ce].line==dl){
                            /* Pattern matched: emit content+nl first, then join */
                            for(int k=cs;k<ce;k++)out[n_out++]=ops[k];
                            out[n_out++]=ops[ce];
                            out[n_out++]=ops[i];
                            i=ce+1;continue;
                        }
                    }
                    out[n_out++]=ops[i];i++;
                }
                pp_write_hunk(&hunk);
                for(int j=0;j<n_out;j++)pp_write_op(&out[j]);
                pp_write_hunk_end();free(out);
            }
            sscanf(line,"HUNK\t%d\t%d\t%d\t%d\t%d",&hunk.target,&hunk.del,&hunk.ins,&hunk.end_ins,&hunk.end_del);
            in_hunk=1;n_ops=0;continue;
        }
        if(strncmp(line,"HUNK_END",8)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0;
                int i=0;
                while(i<n_ops){
                    if(i+2<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code==10&&
                       strcmp(ops[i+1].type,"delete")==0&&ops[i+1].code!=10&&
                       ops[i+1].line==ops[i].line+1){
                        int dl=ops[i].line+1;int cs=i+1,ce=cs;
                        while(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code!=10&&ops[ce].line==dl)ce++;
                        if(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code==10&&ops[ce].line==dl){
                            for(int k=cs;k<ce;k++)out[n_out++]=ops[k];
                            out[n_out++]=ops[ce];out[n_out++]=ops[i];
                            i=ce+1;continue;
                        }
                    }
                    out[n_out++]=ops[i];i++;
                }
                pp_write_hunk(&hunk);
                for(int j=0;j<n_out;j++)pp_write_op(&out[j]);
                pp_write_hunk_end();free(out);
            }
            in_hunk=0;n_ops=0;continue;
        }
        if(in_hunk){if(n_ops>=ops_cap){ops_cap*=2;ops=(Op *)realloc(ops,ops_cap*sizeof(Op));}pp_parse_op(line,&ops[n_ops]);n_ops++;}
    }
    if(in_hunk&&n_ops>0){
        Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op));int n_out=0;
        int i=0;
        while(i<n_ops){
            if(i+2<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code==10&&
               strcmp(ops[i+1].type,"delete")==0&&ops[i+1].code!=10&&
               ops[i+1].line==ops[i].line+1){
                int dl=ops[i].line+1;int cs=i+1,ce=cs;
                while(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code!=10&&ops[ce].line==dl)ce++;
                if(ce<n_ops&&strcmp(ops[ce].type,"delete")==0&&ops[ce].code==10&&ops[ce].line==dl){
                    for(int k=cs;k<ce;k++)out[n_out++]=ops[k];
                    out[n_out++]=ops[ce];out[n_out++]=ops[i];
                    i=ce+1;continue;
                }
            }
            out[n_out++]=ops[i];i++;
        }
        pp_write_hunk(&hunk);
        for(int j=0;j<n_out;j++)pp_write_op(&out[j]);
        pp_write_hunk_end();free(out);
    }
    printf("\n");free(ops);return 0;
}
