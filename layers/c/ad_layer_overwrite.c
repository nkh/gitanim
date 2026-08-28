/* ad_layer_overwrite.c — standalone: merge delete+insert + position adjust */
#include "ad_layer_common.h"
int main(void) {
    char line[PP_MAX_LINE];
    Op *ops=NULL;int n_ops=0,ops_cap=0,in_hunk=0;Hunk hunk={0};
    ops_cap=4096; ops=(Op *)malloc(ops_cap*sizeof(Op));
    while (fgets(line,sizeof(line),stdin)) {
        line[strcspn(line,"\n\r")]=0; if(line[0]==0)continue;
        if(line[0]=='#'){if(strstr(line,"raw diff")||strstr(line,"post-processed"))printf("# diffvim post-processed v2\n");else printf("%s\n",line);continue;}
        if(strncmp(line,"HUNK\t",5)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op)); int n_out=0;
                /* merge */
                int i=0;
                while(i<n_ops){
                    int pd=(i>0&&strcmp(ops[i-1].type,"delete")==0&&ops[i-1].code!=10&&ops[i-1].line==ops[i].line&&ops[i-1].col==ops[i].col);
                    int ni=(i+2<n_ops&&strcmp(ops[i+2].type,"insert")==0&&ops[i+2].code!=10&&ops[i+2].line==ops[i+1].line);
                    if(i+1<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code!=10&&strcmp(ops[i+1].type,"insert")==0&&ops[i+1].code!=10&&ops[i].line==ops[i+1].line&&ops[i].col==ops[i+1].col&&!pd&&!ni){
                        strcpy(out[n_out].type,"overwrite_insert");out[n_out].code=ops[i+1].code;out[n_out].line=ops[i+1].line;out[n_out].col=ops[i+1].col;n_out++;i+=2;
                    }else{out[n_out++]=ops[i];i++;}
                }
                /* set positions */
                {int cl=n_out>0?out[0].line:1,cc=1;for(int i=0;i<n_out;i++){if(pp_is_debug_op(&out[i]))continue;out[i].line=cl;out[i].col=cc;if(strcmp(out[i].type,"keep")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}else if(strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}}}
                /* update offset */
                pp_write_hunk(&hunk);for(int i=0;i<n_out;i++)pp_write_op(&out[i]);pp_write_hunk_end();free(out);
            }
            sscanf(line,"HUNK\t%d\t%d\t%d\t%d\t%d",&hunk.target,&hunk.del,&hunk.ins,&hunk.end_ins,&hunk.end_del);in_hunk=1;n_ops=0;continue;
        }
        if(strncmp(line,"HUNK_END",8)==0){
            if(in_hunk&&n_ops>0){
                Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op)); int n_out=0;
                int i=0;while(i<n_ops){int pd=(i>0&&strcmp(ops[i-1].type,"delete")==0&&ops[i-1].code!=10&&ops[i-1].line==ops[i].line&&ops[i-1].col==ops[i].col);int ni=(i+2<n_ops&&strcmp(ops[i+2].type,"insert")==0&&ops[i+2].code!=10&&ops[i+2].line==ops[i+1].line);if(i+1<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code!=10&&strcmp(ops[i+1].type,"insert")==0&&ops[i+1].code!=10&&ops[i].line==ops[i+1].line&&ops[i].col==ops[i+1].col&&!pd&&!ni){strcpy(out[n_out].type,"overwrite_insert");out[n_out].code=ops[i+1].code;out[n_out].line=ops[i+1].line;out[n_out].col=ops[i+1].col;n_out++;i+=2;}else{out[n_out++]=ops[i];i++;}}
                {int cl=n_out>0?out[0].line:1,cc=1;for(int i=0;i<n_out;i++){if(pp_is_debug_op(&out[i]))continue;out[i].line=cl;out[i].col=cc;if(strcmp(out[i].type,"keep")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}else if(strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}}}
                pp_write_hunk(&hunk);for(int i=0;i<n_out;i++)pp_write_op(&out[i]);pp_write_hunk_end();free(out);
            }
            in_hunk=0;n_ops=0;continue;
        }
        if(in_hunk){if(n_ops>=ops_cap){ops_cap*=2;ops=(Op *)realloc(ops,ops_cap*sizeof(Op));}pp_parse_op(line,&ops[n_ops]);n_ops++;}
    }
    if(in_hunk&&n_ops>0){
        Op *out=(Op *)malloc((n_ops+1024)*sizeof(Op)); int n_out=0;
        int i=0;while(i<n_ops){int pd=(i>0&&strcmp(ops[i-1].type,"delete")==0&&ops[i-1].code!=10&&ops[i-1].line==ops[i].line&&ops[i-1].col==ops[i].col);int ni=(i+2<n_ops&&strcmp(ops[i+2].type,"insert")==0&&ops[i+2].code!=10&&ops[i+2].line==ops[i+1].line);if(i+1<n_ops&&strcmp(ops[i].type,"delete")==0&&ops[i].code!=10&&strcmp(ops[i+1].type,"insert")==0&&ops[i+1].code!=10&&ops[i].line==ops[i+1].line&&ops[i].col==ops[i+1].col&&!pd&&!ni){strcpy(out[n_out].type,"overwrite_insert");out[n_out].code=ops[i+1].code;out[n_out].line=ops[i+1].line;out[n_out].col=ops[i+1].col;n_out++;i+=2;}else{out[n_out++]=ops[i];i++;}}
        {int cl=n_out>0?out[0].line:1,cc=1;for(int i=0;i<n_out;i++){if(pp_is_debug_op(&out[i]))continue;out[i].line=cl;out[i].col=cc;if(strcmp(out[i].type,"keep")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}else if(strcmp(out[i].type,"insert")==0||strcmp(out[i].type,"overwrite_insert")==0){if(out[i].code==10){cl++;cc=1;}else cc++;}}}
        pp_write_hunk(&hunk);for(int i=0;i<n_out;i++)pp_write_op(&out[i]);pp_write_hunk_end();free(out);
    }
    printf("\n");free(ops);return 0;
}
